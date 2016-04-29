WebRedeploy::Engine.routes.draw do
  
  get 'bundle_install' => "app#bundle_install"
  get 'code_environments' => "app#code_environments"
  get 'database_statistics' => "app#database_statistics"
  get 'fetch_origin' => "app#fetch_origin"
  get 'phased_restart' => "app#phased_restart"
  get 'pull_code' => "app#pull_code"
  get 'puma_server_processes' => "app#puma_server_processes"
  get 'sanity_check' => "app#sanity_check"
  get 'switch_branch' => "app#switch_branch"
  get 'tail_log' => "app#tail_log"
  get 'version_info' => "app#version_info"
  
end