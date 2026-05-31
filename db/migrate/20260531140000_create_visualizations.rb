class CreateVisualizations < ActiveRecord::Migration[8.1]
  def change
    create_table :visualizations do |t|
      t.references :query, null: false, foreign_key: true, index: { unique: true }
      t.string :chart_type, null: false, default: "line"
      t.string :x_column
      t.text :y_columns
      t.string :series_column
      t.string :display_mode, null: false, default: "table"
      t.string :counter_column
      t.string :counter_aggregation, null: false, default: "sum"

      t.timestamps
    end
  end
end
