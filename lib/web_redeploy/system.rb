module WebRedeploy
  class System

    @@instance_id = Process.pid  # Every startup of the system should have an instance_id - set it here

    @@startup_git_revision = ""           # The git revisions that this process is running on (recorded at startup time)

    def self.instance_id
      @@instance_id
    end

    def self.register_application_started
      # If this is a server startup, then record this in the deployment log
      if !defined?(::Rake) && !defined?(Rails::Console) && Rails.env.production?
        WebRedeploy::System.write_deployment_log("server-started")
      end
      # Record the git revisions that were checked-out at startup time
      @@startup_git_revision
    end


    def self.check_required_process(stats, process_type)
      instances = stats[:results].select{|pid, data| data[:result][:process_type] == process_type} rescue {}
      instances = instances.map{|pid, data| data[:result]}
      alerts = []
      if instances.blank?
        alerts << "There are no instances of #{process_type} running"
      else
        instances.each do |data|
          if @@startup_git_revision != data[:startup_git_revision] 
            alerts << "An instance of #{process_type} (#{data[:startup_git_revision]}) is out of sync with the Web Application (#{@@startup_git_revision})"
          end
        end
      end
      alerts
    end

    def self.garbage_collect
      GC.start()
      sleep(3)
      memory_statistics
    end


    # Helper to get the memory usage of the current process (in MB)
    def self.memory_statistics
      require 'objspace'
      startup_command = "#{$0} #{$*}"
      { pid: @@instance_id,
        startup_git_revision: @@startup_git_revision,
        used_mb: (((100.0 * (`ps -o rss -p #{$$}`.strip.split.last.to_f / 1024.0)).to_i) / 100.0),
        startup_command: startup_command,
        process_type: lookup_process_type(startup_command),
        count_objects_size: ObjectSpace.count_objects_size,
        gc: GC.stat,
        count_nodes: ObjectSpace.count_nodes
      }
    end

    def self.lookup_process_type(sc)
      if sc == "script/rails []"
        "Rails Console"
      elsif sc =~ /puma/
        "Web Server"
      elsif sc =~ /scheduler/
        "Resque Scheduler"
      elsif sc =~ /resque:work/
        "Resque Worker"
      elsif sc =~ /rules:redis/
        "Rules Engine"
      else
        sc
      end
    end


   # if project is passed in as nil, then it is (by default) the company project
   # pass in run_command = false if you want to test this code - it will remove your changes
    def self.pull_code(run_command = true)
      Rails.logger.info("\033[93mSystem.pull_code\033[0m")
      log_file ||= "#{::Rails.root}/../deployments/pull_#{Time.current.strftime('%F_%H%M%S')}.log"

      da = PyrCore::DeploymentAction.create(  user_id: Thread.current[:user].try(:id),
                                            start_time: Time.current,
                                              event: "pull_#{project_type}",
                                              log_file: log_file )

      branch_info = git_branch # [branch, {local_changes: []}]
      branch = branch_info[0]
      revert_command = ""
      local_changes = branch_info[1][:local_changes]
      if local_changes.present? && Rails.env.production?  # Only actually automatically revert in Production
        revert_command << local_changes.map{|lc| "git checkout -- #{lc}"}.join(" && ")
        revert_command << " && "
      end
      old_revision = git_revision(project)
      cmd = "#{revert_command}git pull origin #{branch}"
      da.command = cmd
      if local_changes.present?
        da.extras[:local_changes] = local_changes
        da.extras[:local_diffs] = {}
        local_changes.each do |lc|
          if lc == "Gemfile.lock" || lc == "db/schema.rb"
            Rails.logger.warn "Not saving diff in DeploymentAction for super common: #{lc}"
            next
          end
          diff_text = `#{pre_command}git diff #{lc}`
          if (diff_text.presence || "").length < 8192
            da.extras[:local_diffs][lc] = diff_text
          else
            Rails.logger.warn "Not writing diff in DeploymentAction cuz it's bigger than 4,096 and don't want the DeploymentAction record to hoark: #{lc}"
          end
        end
      end
      da.extras[:old_revision] = old_revision
      ::Rails.logger.debug("\n\nPyrCore::System.pull_code: [#{cmd}]")
      da.save!
      if run_command
        results = `#{cmd}`
        da.exit_status = $?.exitstatus rescue nil
      else
        results = "run_command was false - no results"
        da.exit_status = 0
      end
      new_revision = git_revision    # get the new revision after the pull
      da.branch = branch
      da.revision = new_revision
      da.command_results = results
      da.end_time = Time.current
      da.save!
      File.open( log_file, "w+") {|f| f.write("#{cmd}\n\n"); f.write("#{results}\n\n"); f.write("Diffs:\n #{da.extras[:local_diffs]}")}
      diff_cache = Rails.cache.fetch("PyrCore::System::diff_cache") do
        {}
      end.with_indifferent_access
      [cmd, results, da.exit_status]
    end

    # Kills all resque tasks and restarts them
    # returns the list of messages summarizing the work performed
    def self.restart_resque_tasks(opts = {})
      return "Already restarting Resque Tasks" if Rails.cache.read("PyrCore::System.restart_resque_tasks")
      Rails.cache.write("PyrCore::System.restart_resque_tasks", true, expires_in: 1.minutes)
      opts[:worker_count] ||= 2
      list = slb("PyrCore::System.restart_resque_tasks")
      # Get all pids of running resque_tasks
      pids = `ps aux | grep [r]esque | grep -v grep | cut -c 10-15`
      slb("Got pids to kill: #{pids}", list)

      pids.split.each do |pid|
        slb("  killing pid[#{pid}]", list)
        `kill -9 #{pid}`
      end

      # Need DYNAMIC_SCHEDULE for Rules engine integration
      cmd = "nohup rake resque:scheduler DYNAMIC_SCHEDULE=true > log/resque-scheduler.log 2>&1 &"
      slb("Restarting resque:scheduler: #{cmd}", list)
      `#{cmd}`

      cmd = "nohup rake resque:workers COUNT=#{opts[:worker_count]} >> log/resque-workers.log 2>&1 &"
      slb("Restarting resque:workers: #{cmd}", list)
      `#{cmd}`

      list
    end

    # slb == SummaryLogBuilder
    def self.slb(message, list = [])
      Rails.logger.info( message )
      list << message
    end

    # Kills the Rules engine process and restarts it
    # returns the list of messages summarizing the work performed
    def self.restart_rules_engine
      return "Already restarting Rules Engine" if Rails.cache.read("PyrCore::System.restart_rules_engine")
      Rails.cache.write("PyrCore::System.restart_rules_engine", true, expires_in: 1.minutes)
      list = slb("PyrCore::System.restart_rules_engine")

      pids = `ps aux | grep [r]ules:redis:processor | grep -v grep | cut -c 10-15`

      slb("Got pids to kill: #{pids}", list)

      pids.split.each do |pid|
        slb("  killing pid[#{pid}]", list)
        `kill -9 #{pid}`
      end

      cmd = "nohup rake rules:redis:processor >> log/rules_engine.log 2>&1 &"
      slb("Restarting resque:scheduler: #{cmd}", list)
      `#{cmd}`

      list
    end

    def self.bundle_install
      log_file ||= "#{::Rails.root}/../deployments/bundle_install_#{Time.current.strftime('%F_%H%M%S')}.log"
      cmd = bundle_install_command("darren")
      da = WebRedeploy::DeploymentAction.create(  user_id: Thread.current[:user].try(:id),
                                            start_time: Time.current,
                                              event: "bundle_install",
                                              log_file: log_file )
      cmd # << " > #{log_file} 2>&1"
      Bundler.with_clean_env do
        `#{cmd} > #{log_file} 2>&1`
      end
      da.exit_status = $?.exitstatus rescue nil
      da.end_time = Time.current
      da.save!
      # File.open( log_file, "w+") {|f| f.write("#{cmd}\n\n"); f.write("#{results}\n\n") }
      results = File.read(log_file)
      [cmd, results, da.exit_status]
    end

    # sudo vi /etc/pam.d/su
    #    auth       sufficient pam_exec.so seteuid quiet /usr/local/sbin/pam-same-user
    #
    # sudo vi /usr/local/sbin/pam-same-user
    #
    #    #!/bin/sh
    #    [ "$PAM_USER" = "$PAM_RUSER" ]
    #
    # sudo chmod a+x /usr/local/sbin/pam-same-user
    def self.bundle_install_command(system_user )
      # "su - #{system_user} -c \"cd #{Rails.root};bundle install\""
      "bundle install"
    end

    def self.get_jira_task_details(task_number, jsession_id)
      #task_number="PYR-4"
      #jsession_id="A8F74A8606B2778FB62E51A234DE21A3.jirapr1"
      curl = "curl 'https://jira2.icentris.com/jira/browse/#{task_number}' -H 'Accept-Encoding: gzip,deflate,sdch' -H 'Accept-Language: en,en-US;q=0.8,es;q=0.6' -H 'User-Agent: Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/36.0.1985.143 Safari/537.36' -H 'Accept: text/html,application/xhtml+xml,application/xml;q=0.9,image/webp,*/*;q=0.8' -H 'Cache-Control: max-age=0' -H 'Cookie: JSESSIONID=#{jsession_id};' --compressed"
      doc = Nokogiri::HTML(`#{curl}`)
      {
        title: doc.css("#summary-val").text,
        client: doc.css("#customfield_10200-val").text,
        component: doc.css("#components-field").text
      }
    end


    # On the server that you'll be deploying...
    # guard --guardfile ../pyr/Guardfile-autobundle
    def self.autobundler_installed?
      processes = (`ps -ef | grep autobundle`).split("\n").select do |p|
        p =~ /Guardfile/
      end
      processes.present?
    end

    # Initiates a phased-restart of the server and returns both the command that was run and the file name where the log information will be written
    def self.phased_restart
      da = PyrCore::DeploymentAction.create(user_id: Thread.current[:user].try(:id),
                                              start_time: Time.current,
                                              event: 'phased-restart')
      cmd, stack = build_restart_command(da)
      Rails.logger.info "\n\nPyrCore::System.phased_restart command:\n\n #{cmd}\n\n"
      log_file = run_async_console_command('phased-restart', cmd, da)
      [cmd, log_file]
    end


# ubuntu@ip-10-165-104-11:~$ ps -ef | grep phased-restart
# pyr       4219  3766  4 16:50 ?        00:00:00 sh -c pumactl -S tmp/puma.state phased-restart >> /home/pyr/pyr-greenzone/../deployments/phased-restart_2015-05-15_105019.log 2>&1
# pyr       4222  4219 53 16:50 ?        00:00:00 ruby /home/pyr/.rvm/gems/ruby-2.1.2/bin/ruby_executable_hooks /home/pyr/.rvm/gems/ruby-2.1.2/bin/pumactl -S tmp/puma.state phased-restart
# ubuntu    4242  3213  0 16:50 pts/3    00:00:00 grep --color=auto phased-restart


    # Detects if a puma phased-restart is currently in progress, and if so returns the time alive as well as the log file
    def self.puma_restart_status
      process = (`ps -ef | grep phased-restart`).split("\n").select do |p|
        p =~ /deployments/
      end.first
      # For development testing
      # process = "pyr       #{PyrCore::System.instance_id}  3766  4 16:50 ?        00:00:00 sh -c pumactl -S tmp/puma.state phased-restart >> /home/pyr/pyr-greenzone/../deployments/phased-restart_2015-05-15_105019.log 2>&1"
      if process.present?
        Rails.logger.info "System.puma_restart_status: [#{process}]"
        parts = process.split
        {user: parts[0], pid: parts[1], time_alive: time_alive(parts[1]), log_file: parts[-2] }
      else
        nil
      end
    end

    # Returns the processids and uptime for all running puma processes
    def self.puma_server_processes
      processes = (`ps -ef | grep puma`).split("\n").select do |p|
        p =~ /cluster worker/ || p=~ /script\/rails/
      end

      # Temporary - if no puma process is running, maybe this is a rake task?
      processes = (`ps -ef | grep rake`).split("\n").select do |p|
        p =~ /bin\/rake/
      end unless processes.present?

      # TODO: also return resque, delayed_job, rules_engine

      servers = processes.map do |s|
        parts = s.split
        { user: parts[0], pid: parts[1]}
      end
      servers.each do |s|
        s[:time_alive] = time_alive(s[:pid])
      end
      servers
    end

    # For a given process ID, get the time alive via a system command
    def self.time_alive(pid)
      time_alive = (`ps -p #{pid} -o etime=`).squish
    end

    def self.write_deployment_log(event_type="server-started", da = nil)
      da ||= PyrCore::DeploymentAction.create(user_id: Thread.current[:user].try(:id),
                                              event: event_type)
      Rails.logger.info "Writing deployment_log[#{event_type}]"
      FileUtils.mkdir "#{::Rails.root}/../deployments" unless File.exist?("#{::Rails.root}/../deployments")
      case event_type
      when "server-started"
        data = PyrCore::System.build_version_info(false)
        data.delete(:last_start_statistics) # don't include previous stats in these stats
        da.extras[:instance_id] = @@instance_id
      else
        data ={}
      end
      data[:timestamp] = Time.current.to_i
      data[:time] = Time.current.strftime("%D %T")
      data[:event] = event_type
      Rails.logger.info "\n\n#{data}\n\n"
      da.update_attributes( data.slice( :company_branch, :company_revision ))
      da.schema_revision = data[:schema]
      da.save!
      File.open("#{::Rails.root}/../deployments/deploy.log", "a") do |f|
        f.write("#{data.to_json}\n")
      end
    end

    # Take the branch that we're currently on, make sure that we are allowed to switch
    # to the new branch.
    def self.switch_branch(new_branch)
      Rails.logger.info("\033[93mSystem.switch_branch(#{new_branch})\033[0m")
      log_file ||= "#{::Rails.root}/../deployments/switch_branch_#{new_branch}_#{Time.current.strftime('%F_%H%M%S')}.log"

      da = PyrCore::DeploymentAction.create(  user_id: Thread.current[:user].try(:id),
                                            start_time: Time.current,
                                              event: "switch_branch_#{new_branch}",
                                              log_file: log_file )
      cmd = "git fetch origin; git checkout #{new_branch}; cd ../pyr; git fetch origin; git checkout #{new_branch}"
      da.command = cmd
      ::Rails.logger.debug("\n\nPyrCore::System.pull_code: [#{cmd}]")
      da.save!
      results = `#{cmd}`
      da.exit_status = $?.exitstatus rescue nil
      da.save!
      [cmd, results, da.exit_status]
    end

    def self.build_version_info(regenerate_diffs=false)
      Rails.logger.info "\033[93mSystem.build_version_info(#{regenerate_diffs})\033[0m"
      start_seconds = Time.now
      t1 = Thread.new do
        [*git_branch, git_revision, git_releases]
      end
      server_processes = puma_server_processes
      company_branch, company_local_changes, company_revision, company_releases = t1.value   # This code blocks until t1 is complete

      t1 = Thread.new do
        ActiveRecord::Base.connection_pool.with_connection do
          {
            partition_id: PARTITION_ID,
            rails_root: ::Rails.root.to_s,
            branch: company_branch,
            releases: company_releases,
            local_changes: company_local_changes,
            revision: company_revision,
            date: `git log -n 1 | grep 'Date:'`.gsub("Date: ","").split("\n").first,
            server_processes: server_processes,
            schema: ActiveRecord::SchemaMigration.order("version desc").limit(1).pluck(:version).first
          }
        end
      end

      diff_cache = Rails.cache.fetch("PyrCore::System::diff_cache") do
        {}
      end.with_indifferent_access

      Rails.logger.info "\033[93mretrieved diff_cache\033[0m: #{diff_cache}"
      m = {}.merge!(diff_cache)

      if regenerate_diffs || diff_cache.blank?
        Rails.logger.info "   REGENERATING DIFFS"
        t2 = Thread.new do
          `git fetch origin #{company_branch}`
          [`git diff --shortstat #{company_branch} origin/#{company_branch}`.strip,
          `git diff --name-only #{company_branch} origin/#{company_branch}`.strip]
        end

        `cd ../pyr;git fetch origin #{pyr_branch}`
        pyr_diff = `cd ../pyr;git diff --shortstat #{pyr_branch} origin/#{pyr_branch}`.strip

        diff, diff_files = t2.value
        diff_cache[:diff] = diff
        diff_cache[:diff_files] = diff_files
        Rails.logger.info "\033[93mstoring diff_cache\033[0m: #{diff_cache}"
        Rails.cache.write("PyrCore::System::diff_cache", diff_cache, expires_in: 5.minutes)
      end
      m[:last_start_statistics] = get_last_start_statistics
      m.merge!(t1.value)    # again - this will block until t1 is complete
      m[:time_to_build] = Time.now - start_seconds
      Rails.logger.info "\033[93m   BUILT version_info\033[0m: #{m}"
      m.with_indifferent_access
    end

    # eg: git_revision("../pyr")
    def self.git_revision
      rev = `git log -n 1 | grep 'commit'`.gsub("commit ","").split("\n").first
      rev.gsub!("# ", "") if rev.start_with?("# ")  # sometimes git output has '# ' before each line of output
      rev
    end

    # eg: git_releases("../pyr")
    def self.git_releases
      releases = `git branch -a`.split.map do |b|
        n = b.split("/").last; (n.length <= 4 && n =~ /\./) ? n : nil
      end.compact.sort.uniq
    end

    # eg: git_branch("../pyr")
    #
    # returns [branchName, { local_changess: [file1, file2] }]
    #
    def self.git_branch
      results = `git status`
      lines = results.split("\n")
      lines.each{|l| l.gsub!(/^#/, ""); l.squish!}
      branch = lines[0].gsub("On branch", "").squish
      local_changes = lines.select{|l| l =~ /modified:/}.map{|l| l.gsub("modified:", "").squish }

      # branch.gsub!("# ", "") if branch.start_with?("# ")  # sometimes git output has '# ' before each line of output
      [branch, {local_changes: local_changes}]
    end

    # Runs the command in the background with output going to log_file
    # Returns log_file
    def self.run_async_console_command(name, command, da = nil)   # da is a DeploymentAction
      log_file ||= "#{::Rails.root}/../deployments/#{name}_#{Time.current.strftime('%F_%H%M%S')}.log"
      cmd_parts = command.split("&&")
      bundler_status = nil
      if cmd_parts.first.squish == "bundle install"
        cmd_parts.shift # We'll handle 'bundle install' remove it from the rest of the results
        Bundler.with_clean_env do
          `bundle install > #{log_file} 2>&1`
          bundler_status = $?.exit_status rescue nil
        end
      end
      File.open( log_file, "a+") {|f| f.write("#{command}\n\n")}
      command_with_logging = cmd_parts.map {|cmd| "#{cmd} >> #{log_file} 2>&1"}.join(" && ")
      if da
        da.command = command_with_logging
        da.log_file = log_file
        da.save!
      end
      Thread.new(da, log_file, command_with_logging, bundler_status) do |da, log_file, cmd, bundler_status|
        ActiveRecord::Base.connection_pool.with_connection do
          if bundler_status && bundler_status != 0
            exit_status = bundler_status
          else
            `#{cmd}`
            exit_status = $?.exitstatus rescue nil
          end
          if exit_status && exit_status != 0
            msg = "ERROR: Execution failed with EXIT_STATUS = #{exit_status}!!!"
          else
            msg = "Execution completed without errors"
          end
          File.open( log_file, "a+") {|f| f.write("\n\n#{msg}")}
          if da
            # I think this causes file to rollback - good enough that it's in the log file
            #da.command_results = File.read(log_file) rescue "Error reading log file"
            da.end_time = Time.current
            da.exit_status = exit_status
            da.save!
          end
        end
      end
      log_file
    end


    def self.get_last_start_statistics
      begin
        File.readlines("#{::Rails.root}/../deployments/deploy.log").reverse_each do |l|
          #puts l
          stats = JSON.parse(l)
          case stats["event"]
          when 'server-started'
            return stats.with_indifferent_access
          else
          end
        end
        nil
      rescue => e
        ::Rails.logger.error(e)
        nil
      end
    end


    def self.build_restart_command(da = nil, include_deploy: true, include_restart: true)  # PyrCore::DeploymentAction
      cmd = ""
      task_chain = []
      if include_deploy
        restart_info = compute_restart_tasks(nil, da)
        task_chain = restart_info[:task_chain]
        puts "\ntask_chain: #{task_chain}\n"
        if task_chain.index(:bundle_install)
          bic = bundle_install_command(restart_info[:system_user])
          cmd += "#{bic} && "
        end
        rake_parts = ""
        rake_parts += " db:migrate" if task_chain.index(:db_migrate)
        rake_parts += " pyr:security:load" if task_chain.index(:security_load)
        rake_parts += " pyr:load_route_pages" if task_chain.index(:load_route_pages)
        rake_parts += " assets:precompile" if task_chain.index(:assets_precompile)
        rake_parts += " pyr:cms:load_model_overrides" if task_chain.index(:cms_load_model_overrides)
        rake_parts += " pyr:migrate_nav" if task_chain.index(:migrate_nav)
        rake_parts += " pyr:cms:delete_cms_keys" if task_chain.index(:delete_cms_keys)
        rake_parts += " pyr:widget:deprecate" if task_chain.index(:widget_deprecate)
        cmd += "rake #{rake_parts}" if rake_parts.present?
        cmd = "RUBY UPGRADE REQUIRED; #{cmd}" if task_chain.index(:ruby_upgrade)
      end

      if include_restart
        cmd += " && " if cmd.present?
        if PyrCore::AppSetting.application_server == 'puma'
          cmd += "pumactl -S tmp/puma.state phased-restart"
        else
          cmd += "passenger-config restart-app /"
        end
      end
      [cmd, task_chain]
    end


    # Look at the most recent deployment revisions and determine what needs to be done
    # to restart code based on what is currently brought down from Github
    def self.compute_restart_tasks(stat_now = nil, da = nil)  # da == PyrCore::DeploymentAction
      Rails.logger.info("System.compute_restart_tasks")
      stat_then = get_last_start_statistics   # Revisions as of last server start
      task_chain = [:phased_restart]
      stat_now ||= PyrCore::System.build_version_info(false)   # Revisions currently checked out
      Rails.logger.info("stat_now = #{stat_now}")
      system_user = stat_now[:server_processes].first[:user] rescue nil
      if stat_then
        diff = git_file_diff(stat_then[:company_revision], stat_now[:company_revision])
        Rails.logger.info("diff: #{diff}")
        if da && Rails.env.production?  # This could be ginormous locally cuz stat_then could be ancient
          da.extras[:stat_then] = stat_then
          da.extras[:stat_now] = stat_now
          da.extras[:diff] = diff
          da.save!
        end
        task_chain.unshift(:ruby_upgrade) if full_diff.index(".ruby-version")
        task_chain.unshift(:assets_precompile) if full_diff.detect{|f| is_asset_precompile_file(f)} || full_diff.index("Gemfile.lock") || pyr_diff.index("common_pyr_dependencies.rb")
        task_chain.unshift(:db_migrate) if pyr_diff.detect{|f| f.start_with?("db-migrate")} || diff.detect{|f| f.start_with?("db/migrate")}
        task_chain.unshift(:bundle_install) if full_diff.index("Gemfile.lock") || pyr_diff.index("common_pyr_dependencies.rb")
        if da
          da.required_bundle_install = task_chain.include?(:bundle_install)
          da.required_migrations = task_chain.include?(:db_migrate)
          da.required_assets_precompile = task_chain.include?(:assets_precompile)
          da.save!
        end
      end
      r = { system_user: system_user, task_chain: task_chain, last_start: stat_then, diff: diff }.with_indifferent_access
      Rails.logger.info( "returning: #{r}")
      r
    end

    def self.git_file_diff(revision_old, revision_new)
      diff = `git diff --numstat #{revision_old}..#{revision_new}`.split("\n")
      diff.map{|f| f.match(/.*\t.*\t(.*)/)[1] rescue f}.sort
    end


    private
      def self.is_asset_precompile_file(f)
        f.index(".js") || f.index(".css") || f.index("app/assets/")  # Maybe use Rails definition of assets
      end

      def self.is_navigation_file(f)
        f.index("routes.rb")
      end

  end
end
