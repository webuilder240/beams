class CreateQueries < ActiveRecord::Migration[8.1]
  def change
    create_table :queries do |t|
      t.string :title, null: false
      t.text :sql_body, null: false
      t.references :user, null: false, foreign_key: true
      t.references :bigquery_connection, null: false, foreign_key: true

      t.timestamps
    end
  end
end
