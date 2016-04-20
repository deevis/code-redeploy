Rails.application.routes.draw do

  mount WebRedeploy::Engine => "/web_redeploy"

  root to: "web_redeploy/app#code_environments"
end
