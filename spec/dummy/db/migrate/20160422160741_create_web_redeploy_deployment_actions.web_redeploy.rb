# This migration comes from web_redeploy (originally 20130207115149)
class CreateWebRedeployDeploymentActions < ActiveRecord::Migration
  def change
    create_table :web_redeploy_deployment_actions do |t|
      t.integer :user_id
      t.string :revision
      t.string :branch
      t.string :schema_revision
      t.boolean :required_migrations, default: false
      t.boolean :required_bundle_install, default: false 
      t.boolean :required_assets_precompile, default: false
      t.text :extras
      t.string :event,  limit: 30
      t.string :command, limit: 500
      t.text :command_results, limit: 16777215
      t.string :log_file, limit: 300
      t.integer :exit_status
      t.datetime :start_time
      t.datetime :end_time

      t.timestamps null: true # https://github.com/rails/rails/pull/16481
    end
  end
end
