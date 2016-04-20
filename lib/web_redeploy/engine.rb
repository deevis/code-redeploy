module WebRedeploy
  class Engine < ::Rails::Engine
    isolate_namespace WebRedeploy
  end
end