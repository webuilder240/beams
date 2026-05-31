class CreateWidgets < ActiveRecord::Migration[8.1]
  def change
    create_table :widgets do |t|
      t.references :dashboard, null: false, foreign_key: true, index: false
      t.references :query, null: false, foreign_key: true
      t.integer :position, null: false, default: 0
      t.integer :column_span, null: false, default: 1
      t.string :title_override

      t.timestamps
    end

    add_index :widgets, [ :dashboard_id, :position ]
  end
end
