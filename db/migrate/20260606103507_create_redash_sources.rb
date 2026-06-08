class CreateRedashSources < ActiveRecord::Migration[8.1]
  def change
    create_table :redash_sources do |t|
      t.string :name, null: false
      t.string :url,  null: false
      t.text   :api_key, null: false
      t.timestamps
    end

    add_index :redash_sources, :name, unique: true
  end
end
