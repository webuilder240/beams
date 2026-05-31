class CreateQueryExecutions < ActiveRecord::Migration[8.1]
  def change
    create_table :query_executions do |t|
      t.references :query, null: false, foreign_key: true
      t.string :status, null: false, default: "pending"
      t.text :error_message
      t.binary :result_blob
      t.integer :result_row_count
      t.boolean :result_truncated, default: false
      t.text :result_schema
      t.datetime :started_at
      t.datetime :finished_at

      t.timestamps
    end

    add_index :query_executions, :status
    add_index :query_executions, [ :query_id, :status ]
  end
end
