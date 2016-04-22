# -*- encoding: utf-8 -*-
$:.push File.dirname(__FILE__) + '/lib'
require 'web_redeploy/version'

Gem::Specification.new do |gem|
  gem.name = %q{web_redeploy}

  gem.required_rubygems_version = Gem::Requirement.new(">= 0") if gem.respond_to? :required_rubygems_version=
  gem.authors = ["Darren Hicks"]
  gem.description = %q{Gem that provides an admin console to allow code to be pulled from github and server restarted}
  gem.email = %q{darren.hicks@gmail.com}
  gem.extra_rdoc_files = ["README.md", "LICENSE"]

  gem.date = %q{2016-04-13}
  gem.summary = "Web-based code redeploys"

  gem.add_runtime_dependency 'rails'
  gem.add_runtime_dependency 'haml'
  
  gem.add_development_dependency 'byebug'
  gem.add_development_dependency 'better_errors'
  gem.add_development_dependency 'binding_of_caller'
  gem.add_development_dependency 'rspec'
  gem.add_development_dependency 'sqlite3'

  #gem.executables   = `git ls-files -- bin/*`.split("\n").map{ |f| File.basename(f) }
  #gem.files         = `git ls-files`.split("\n")
  gem.files         = ["lib/acts_as_limitable.rb", "lib/code_redeploy/version.rb"]
  gem.test_files    = `git ls-files -- {test,spec,features}/*`.split("\n")
  gem.require_paths = ['lib']
  gem.version       = WebRedeploy::VERSION
end