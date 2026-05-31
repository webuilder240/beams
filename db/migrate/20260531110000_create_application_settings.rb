class CreateApplicationSettings < ActiveRecord::Migration[8.1]
  def change
    create_table :application_settings do |t|
      t.decimal :bigquery_yen_per_tb, precision: 10, scale: 2, null: false, default: 950.0

      t.timestamps
    end
  end
end
