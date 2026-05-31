# This file is auto-generated from the current state of the database. Instead
# of editing this file, please use the migrations feature of Active Record to
# incrementally modify your database, and then regenerate this schema definition.
#
# This file is the source Rails uses to define your schema when running `bin/rails
# db:schema:load`. When creating a new database, `bin/rails db:schema:load` tends to
# be faster and is potentially less error prone than running all of your
# migrations from scratch. Old migrations may fail to apply correctly if those
# migrations use external dependencies or application code.
#
# It's strongly recommended that you check this file into your version control system.

ActiveRecord::Schema[8.1].define(version: 2026_05_31_130000) do
  create_table "application_settings", force: :cascade do |t|
    t.decimal "bigquery_yen_per_tb", precision: 10, scale: 2, default: "950.0", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
  end

  create_table "bigquery_connections", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.bigint "maximum_bytes_billed"
    t.string "name", null: false
    t.string "project_id", null: false
    t.text "service_account_json", null: false
    t.datetime "updated_at", null: false
  end

  create_table "queries", force: :cascade do |t|
    t.integer "bigquery_connection_id", null: false
    t.datetime "created_at", null: false
    t.text "sql_body", null: false
    t.string "title", null: false
    t.datetime "updated_at", null: false
    t.integer "user_id", null: false
    t.index ["bigquery_connection_id"], name: "index_queries_on_bigquery_connection_id"
    t.index ["user_id"], name: "index_queries_on_user_id"
  end

  create_table "query_executions", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.text "error_message"
    t.datetime "finished_at"
    t.integer "query_id", null: false
    t.binary "result_blob"
    t.integer "result_row_count"
    t.text "result_schema"
    t.boolean "result_truncated", default: false
    t.datetime "started_at"
    t.string "status", default: "pending", null: false
    t.datetime "updated_at", null: false
    t.index ["query_id", "status"], name: "index_query_executions_on_query_id_and_status"
    t.index ["query_id"], name: "index_query_executions_on_query_id"
    t.index ["status"], name: "index_query_executions_on_status"
  end

  create_table "query_parameters", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "name", null: false
    t.string "param_type", null: false
    t.integer "query_id", null: false
    t.datetime "updated_at", null: false
    t.index ["query_id", "name"], name: "index_query_parameters_on_query_id_and_name", unique: true
    t.index ["query_id"], name: "index_query_parameters_on_query_id"
  end

  create_table "users", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "email", null: false
    t.string "password_digest", null: false
    t.string "role", default: "member", null: false
    t.datetime "updated_at", null: false
    t.index ["email"], name: "index_users_on_email", unique: true
  end

  add_foreign_key "queries", "bigquery_connections"
  add_foreign_key "queries", "users"
  add_foreign_key "query_executions", "queries"
  add_foreign_key "query_parameters", "queries"
end
