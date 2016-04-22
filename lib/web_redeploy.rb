require "web_redeploy/engine"
require "web_redeploy/system"
require 'haml'

module WebRedeploy

  mattr_accessor :restart_command 
  @@restart_command = "pumactl -S tmp/puma.state phased-restart" 

  mattr_accessor :authorize_user 
  @@authorize_user = -> (user) { user.present? && user.try(:admin?) } 

end