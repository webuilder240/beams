# 可視化（トピック11）のビュー補助。取得済み結果（`QueryExecution#result` の
# `{schema:, rows:}`）から Chart.js の `{ type:, data: }` 設定を組み立てる。
# **BigQuery には再クエリしない**（表示用 blob を入力とする）。
# counter は Chart.js を使わず単一値表示のため、ここでは扱わない（Visualization#counter_value）。
module VisualizationHelper
  # 結果の列名一覧（軸ドロップダウン用）。結果が無ければ空配列。
  def result_columns(execution)
    result = execution&.result
    return [] if result.nil?

    Array(result[:schema]).map { |col| col["name"] }
  end

  # counter（カウンター）の集計値を表示用に整形する。整数に割り切れる値は
  # 整数表示（60.0→"60"）、小数はそのまま（20.5→"20.5"）。nil は "—"。
  # `counter_value` の戻り値型は変えず、表示整形のみ担う。
  def format_counter_value(value)
    return "—" if value.nil?
    return value.to_i.to_s if value.respond_to?(:to_i) && value == value.to_i

    value.to_s
  end

  # Chart.js へ渡す設定（{ type:, data: }）を組み立てる。
  # 軸未設定・結果未保存・指定列がスキーマに無い場合は nil（描画しない）。
  def chart_config_for(visualization, execution)
    result = execution&.result
    return nil if result.nil?
    return nil if visualization.x_column.blank?

    y_columns = Array(visualization.y_columns).compact_blank
    return nil if y_columns.empty?

    schema = Array(result[:schema])
    rows = result[:rows]
    x_index = column_index(schema, visualization.x_column)
    return nil if x_index.nil?

    if visualization.chart_type == "scatter"
      scatter_config(rows, x_index, schema, y_columns)
    else
      cartesian_config(visualization, rows, x_index, schema, y_columns)
    end
  end

  private

  def column_index(schema, name)
    schema.index { |col| col["name"] == name }
  end

  def cartesian_config(visualization, rows, x_index, schema, y_columns)
    labels = rows.map { |row| row[x_index] }
    fill = visualization.chart_type == "area"
    js_type = visualization.chart_type == "area" ? "line" : visualization.chart_type

    datasets = y_columns.filter_map do |y|
      y_index = column_index(schema, y)
      next if y_index.nil?

      { label: y, data: rows.map { |row| row[y_index] }, fill: fill }
    end

    { type: js_type, data: { labels: labels, datasets: datasets } }
  end

  def scatter_config(rows, x_index, schema, y_columns)
    y = y_columns.first
    y_index = column_index(schema, y)
    return nil if y_index.nil?

    points = rows.map { |row| { x: row[x_index], y: row[y_index] } }
    { type: "scatter", data: { datasets: [ { label: y, data: points } ] } }
  end
end
