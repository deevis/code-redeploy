WebRedeploy::Engine.routes.draw do
  
  get 'code_environments' => "app#code_environments"
  get 'database_statistics' => "app#database_statistics"
  get 'phased_restart' => "app#phased_restart"
  get 'pull_code' => "app#pull_code"
  get 'sanity_check' => "app#sanity_check"
  get 'switch_branch' => "app#switch_branch"
  get 'tail_log' => "app#tail_log"
  get 'version_info' => "app#version_info"
  
end