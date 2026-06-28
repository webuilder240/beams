# frozen_string_literal: true

require "test_helper"

class VisualizationHelperTest < ActionView::TestCase
  def execution_with(schema:, rows:)
    exec = build_query_execution
    exec.store_result(schema, rows)
    exec
  end

  def sample_execution
    execution_with(
      schema: [
        { "name" => "day", "type" => "STRING" },
        { "name" => "sales", "type" => "INTEGER" },
        { "name" => "cost", "type" => "INTEGER" }
      ],
      rows: [ [ "Mon", 10, 4 ], [ "Tue", 20, 8 ], [ "Wed", 30, 12 ] ]
    )
  end

  # --- #chart_config_for ---

  test "returns a hash with type and data for a line chart" do
    viz = build_visualization(chart_type: "line", x_column: "day", y_columns: %w[sales])
    config = chart_config_for(viz, sample_execution)

    assert_equal "line", config[:type]
    assert_equal %w[Mon Tue Wed], config[:data][:labels]
    assert_equal "sales", config[:data][:datasets].first[:label]
    assert_equal [ 10, 20, 30 ], config[:data][:datasets].first[:data]
  end

  test "supports multiple y columns" do
    viz = build_visualization(chart_type: "bar", x_column: "day", y_columns: %w[sales cost])
    config = chart_config_for(viz, sample_execution)

    assert_equal "bar", config[:type]
    assert_equal 2, config[:data][:datasets].size
    assert_equal %w[sales cost], config[:data][:datasets].map { |d| d[:label] }
  end

  test "maps area to a filled line chart" do
    viz = build_visualization(chart_type: "area", x_column: "day", y_columns: %w[sales])
    config = chart_config_for(viz, sample_execution)

    assert_equal "line", config[:type]
    assert_equal true, config[:data][:datasets].first[:fill]
  end

  test "returns nil when the execution has no result" do
    viz = build_visualization(chart_type: "line", x_column: "day", y_columns: %w[sales])
    assert_nil chart_config_for(viz, build_query_execution)
  end

  test "returns nil when axes are not configured" do
    viz = build_visualization(chart_type: "line", x_column: nil, y_columns: nil)
    assert_nil chart_config_for(viz, sample_execution)
  end

  test "builds scatter data as {x, y} points using the first y column" do
    viz = build_visualization(chart_type: "scatter", x_column: "sales", y_columns: %w[cost])
    config = chart_config_for(viz, sample_execution)

    assert_equal "scatter", config[:type]
    assert_equal(
      [ { x: 10, y: 4 }, { x: 20, y: 8 }, { x: 30, y: 12 } ],
      config[:data][:datasets].first[:data]
    )
  end

  # --- #result_columns ---

  test "returns the column names from the execution result" do
    assert_equal %w[day sales cost], result_columns(sample_execution)
  end

  test "returns an empty array when there is no result" do
    assert_equal [], result_columns(build_query_execution)
  end

  # --- #format_counter_value ---

  test "shows a whole number without a decimal point" do
    assert_equal "60", format_counter_value(60.0)
  end

  test "keeps a fractional value as-is" do
    assert_equal "20.5", format_counter_value(20.5)
  end

  test "shows an integer count as an integer" do
    assert_equal "2", format_counter_value(2)
  end

  test "shows a dash for nil" do
    assert_equal "—", format_counter_value(nil)
  end
end
