class WebRedeploy::DeploymentAction < ActiveRecord::Base
  serialize :extras, Hash 
  
  belongs_to :user 


end