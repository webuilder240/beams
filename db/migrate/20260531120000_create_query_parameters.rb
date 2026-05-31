class CreateQueryParameters < ActiveRecord::Migration[8.1]
  def change
    create_table :query_parameters do |t|
      t.references :query, null: false, foreign_key: true
      t.string :name, null: false
      t.string :param_type, null: false

      t.timestamps
    end

    add_index :query_parameters, [ :query_id, :name ], unique: true
  end
end
