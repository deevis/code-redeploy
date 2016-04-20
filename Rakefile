require 'rubygems'
require 'bundler'
require 'rake'
require 'rake/testtask'
require 'rspec/core'
require 'rspec/core/rake_task'
require 'active_support/dependencies'   # for require_dependency
Bundler.setup :default, :development

desc 'Default: run specs'
task :default => :spec  

require 'rspec/core/rake_task'
RSpec::Core::RakeTask.new do |t|
  t.pattern = "spec/**/*_spec.rb"
end

Bundler::GemHelper.install_tasks

desc 'Generates a dummy app for testing'
task :dummy_app => [:test_environment, :setup, :migrate]

task :test_environment do
  ENV["RAILS_ENV"] ||= "test"    # set to test, unless someone explicitly set something else
end

task :setup do
  require 'rails'
  require 'action_controller'
  require 'web_redeploy'

  dummy = File.expand_path('spec/dummy', COMMAND_DIRECTORY)
  sh "rm -rf #{dummy}"
  WebRedeploy::Engine.start(
    web_redeploy --quiet --force --skip-bundle --old-style-hash --dummy-path=#{dummy})
  )
end
