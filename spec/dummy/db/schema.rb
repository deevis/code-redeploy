# encoding: UTF-8
# This file is auto-generated from the current state of the database. Instead
# of editing this file, please use the migrations feature of Active Record to
# incrementally modify your database, and then regenerate this schema definition.
#
# Note that this schema.rb definition is the authoritative source for your
# database schema. If you need to create the application database on another
# system, you should be using db:schema:load, not running all the migrations
# from scratch. The latter is a flawed and unsustainable approach (the more migrations
# you'll amass, the slower it'll run and the greater likelihood for issues).
#
# It's strongly recommended that you check this file into your version control system.

ActiveRecord::Schema.define(version: 20160422160741) do

  create_table "web_redeploy_deployment_actions", force: :cascade do |t|
    t.integer  "user_id"
    t.string   "revision"
    t.string   "branch"
    t.string   "schema_revision"
    t.boolean  "required_migrations",                         default: false
    t.boolean  "required_bundle_install",                     default: false
    t.boolean  "required_assets_precompile",                  default: false
    t.text     "extras"
    t.string   "event",                      limit: 30
    t.string   "command",                    limit: 500
    t.text     "command_results",            limit: 16777215
    t.string   "log_file",                   limit: 300
    t.datetime "start_time"
    t.datetime "end_time"
    t.datetime "created_at"
    t.datetime "updated_at"
  end

end
