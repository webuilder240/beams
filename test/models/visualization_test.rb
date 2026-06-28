require "test_helper"

class VisualizationTest < ActiveSupport::TestCase
  # --- associations ---
  test "responds to query" do
    assert_respond_to Visualization.new, :query
  end

  test "belongs to a query" do
    query = create_query
    viz = create_visualization(query: query)
    assert_equal query, viz.query
  end

  test "is destroyed when its query is destroyed" do
    query = create_query
    create_visualization(query: query)
    before = Visualization.count
    query.destroy
    assert_equal before - 1, Visualization.count
  end

  test "enforces one visualization per query (has_one)" do
    query = create_query
    create_visualization(query: query)
    dup = build_visualization(query: query)
    assert_not dup.valid?
  end

  # --- validations ---
  test "accepts the allowed chart types" do
    %w[line bar pie area scatter counter].each do |type|
      assert build_visualization(chart_type: type).valid?, "expected chart_type=#{type} to be valid"
    end
  end

  test "rejects an unknown chart type" do
    assert_not build_visualization(chart_type: "doughnut").valid?
  end

  test "accepts the allowed display modes" do
    %w[table chart].each do |mode|
      assert build_visualization(display_mode: mode).valid?, "expected display_mode=#{mode} to be valid"
    end
  end

  test "rejects an unknown display mode" do
    assert_not build_visualization(display_mode: "grid").valid?
  end

  test "accepts the allowed counter aggregations" do
    %w[sum avg count min max].each do |agg|
      assert build_visualization(counter_aggregation: agg).valid?, "expected counter_aggregation=#{agg} to be valid"
    end
  end

  test "rejects an unknown counter aggregation" do
    assert_not build_visualization(counter_aggregation: "median").valid?
  end

  # --- y_columns serialization ---
  test "round-trips an array of strings" do
    viz = create_visualization(y_columns: %w[col_a col_b])
    assert_equal %w[col_a col_b], viz.reload.y_columns
  end

  test "defaults to nil when not set" do
    viz = create_visualization
    assert_nil viz.reload.y_columns
  end

  # --- #counter_value ---
  def execution_with(schema:, rows:)
    exec = build_query_execution
    exec.store_result(schema, rows)
    exec
  end

  def default_execution
    execution_with(
      schema: [ { "name" => "amount", "type" => "INTEGER" }, { "name" => "label", "type" => "STRING" } ],
      rows: [ [ 10, "a" ], [ 20, "b" ], [ 30, "c" ] ]
    )
  end

  test "computes the sum of the counter column" do
    viz = build_visualization(chart_type: "counter", counter_column: "amount")
    viz.counter_aggregation = "sum"
    assert_equal 60, viz.counter_value(default_execution)
  end

  test "computes the average" do
    viz = build_visualization(chart_type: "counter", counter_column: "amount")
    viz.counter_aggregation = "avg"
    assert_equal 20, viz.counter_value(default_execution)
  end

  test "computes the min" do
    viz = build_visualization(chart_type: "counter", counter_column: "amount")
    viz.counter_aggregation = "min"
    assert_equal 10, viz.counter_value(default_execution)
  end

  test "computes the max" do
    viz = build_visualization(chart_type: "counter", counter_column: "amount")
    viz.counter_aggregation = "max"
    assert_equal 30, viz.counter_value(default_execution)
  end

  test "counts the non-null values" do
    viz = build_visualization(chart_type: "counter", counter_column: "amount")
    viz.counter_aggregation = "count"
    exec = execution_with(
      schema: [ { "name" => "amount", "type" => "INTEGER" } ],
      rows: [ [ 10 ], [ nil ], [ 30 ] ]
    )
    assert_equal 2, viz.counter_value(exec)
  end

  test "returns nil when the counter column is not set" do
    viz = build_visualization(chart_type: "counter", counter_column: "amount")
    viz.counter_column = nil
    assert_nil viz.counter_value(default_execution)
  end

  test "returns nil when the column is not present in the schema" do
    viz = build_visualization(chart_type: "counter", counter_column: "amount")
    viz.counter_column = "missing"
    assert_nil viz.counter_value(default_execution)
  end

  test "returns nil when the execution has no result" do
    viz = build_visualization(chart_type: "counter", counter_column: "amount")
    assert_nil viz.counter_value(build_query_execution)
  end

  test "treats non-numeric values as zero for sum (safe side)" do
    viz = build_visualization(chart_type: "counter", counter_column: "amount")
    exec = execution_with(
      schema: [ { "name" => "amount", "type" => "STRING" } ],
      rows: [ [ "x" ], [ "y" ] ]
    )
    viz.counter_aggregation = "sum"
    assert_equal 0, viz.counter_value(exec)
  end

  test "returns nil for avg/min/max when there are no numeric values" do
    viz = build_visualization(chart_type: "counter", counter_column: "amount")
    exec = execution_with(
      schema: [ { "name" => "amount", "type" => "STRING" } ],
      rows: [ [ "x" ], [ "y" ] ]
    )
    %w[avg min max].each do |agg|
      viz.counter_aggregation = agg
      assert_nil viz.counter_value(exec)
    end
  end
end
