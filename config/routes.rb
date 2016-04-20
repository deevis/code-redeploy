WebRedeploy::Engine.routes.draw do
  
  get 'code_environments' => "app#code_environments"
  get 'database_statistics' => "app#database_statistics"
  get 'sanity_check' => "app#sanity_check"
  get 'pull_code' => "app#pull_code"
  get 'switch_branch' => "app#switch_branch"
  get 'phased_restart' => "app#phased_restart"
  get 'tail_log' => "app#tail_log"
  
end