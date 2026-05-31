class CreateBigqueryConnections < ActiveRecord::Migration[8.1]
  def change
    create_table :bigquery_connections do |t|
      t.string :name, null: false
      t.string :project_id, null: false
      t.text :service_account_json, null: false
      t.bigint :maximum_bytes_billed

      t.timestamps
    end
  end
end
