require "web_redeploy/engine"
require 'haml'

module WebRedeploy

  mattr_accessor :restart_command 
  @@restart_command = "pumactl -S tmp/puma.state phased-restart" 

  mattr_accessor :authorize_user 
  @@authorize_user = -> (user) { user.present? && user.try(:admin?) } 

  mattr_accessor :allow_redeploy
  @@allow_redeploy = Rails.env.production?

end