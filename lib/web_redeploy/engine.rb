module WebRedeploy
  class Engine < ::Rails::Engine
    isolate_namespace WebRedeploy

    config.autoload_paths += Dir["#{config.root}/lib/**/"]

    initializer 'register_startup' do |app|
      WebRedeploy::System.register_application_started
    end

  end
end