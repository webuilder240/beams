require "test_helper"

class QueryExecutionTest < ActiveSupport::TestCase
  # --- associations ---
  test "belongs to a query" do
    execution = build_query_execution
    assert_kind_of Query, execution.query
  end

  test "is destroyed when its query is destroyed" do
    execution = create_query_execution
    query = execution.query
    before = QueryExecution.count
    query.destroy
    assert_equal before - 1, QueryExecution.count
  end

  # --- enum status ---
  test "defines pending/running/succeeded/failed" do
    assert_equal({
      "pending" => "pending",
      "running" => "running",
      "succeeded" => "succeeded",
      "failed" => "failed"
    }, QueryExecution.statuses)
  end

  test "defaults to pending" do
    assert_equal "pending", build_query_execution.status
  end

  test "supports the predicate and bang transitions" do
    execution = create_query_execution
    execution.running!
    assert_predicate execution, :running?
    execution.succeeded!
    assert_predicate execution, :succeeded?
    execution.failed!
    assert_predicate execution, :failed?
  end

  test "raises on an unknown status" do
    assert_raises(ArgumentError) { build_query_execution(status: "bogus") }
  end

  # --- validations ---
  test "requires a status" do
    execution = build_query_execution
    execution.status = nil
    assert_not execution.valid?
    assert_predicate execution.errors[:status], :present?
  end

  # --- .recent ---
  test "orders executions by created_at descending (newest first)" do
    query = create_query
    older = create_query_execution(query: query, created_at: 2.hours.ago)
    newer = create_query_execution(query: query, created_at: 1.hour.ago)
    newest = create_query_execution(query: query, created_at: Time.current)

    assert_equal [ newest, newer, older ], query.query_executions.recent.to_a
  end

  # --- #duration ---
  test "returns the elapsed seconds between started_at and finished_at" do
    execution = build_query_execution(started_at: Time.utc(2026, 5, 31, 12, 0, 0), finished_at: Time.utc(2026, 5, 31, 12, 0, 3))
    assert_equal 3.0, execution.duration
  end

  test "returns nil when started_at is missing" do
    assert_nil build_query_execution(started_at: nil, finished_at: Time.current).duration
  end

  test "returns nil when finished_at is missing" do
    assert_nil build_query_execution(started_at: Time.current, finished_at: nil).duration
  end

  # --- #succeeded_with_result? ---
  test "is true for a succeeded execution that has a result blob" do
    execution = create_succeeded_query_execution
    execution.store_result([ { "name" => "n", "type" => "INTEGER" } ], [ [ 1 ] ])
    execution.save!
    assert_predicate execution, :succeeded_with_result?
  end

  test "is false for a succeeded execution without a result blob" do
    execution = create_succeeded_query_execution
    assert_not execution.succeeded_with_result?
  end

  test "is false for a failed execution even with a blob" do
    execution = create_failed_query_execution
    execution.store_result([ { "name" => "n", "type" => "INTEGER" } ], [ [ 1 ] ])
    execution.save!
    assert_not execution.succeeded_with_result?
  end

  # --- #store_result and #result (JSON + gzip round trip) ---
  test "writes a gzip-compressed JSON blob to result_blob" do
    execution = create_query_execution
    schema = [ { "name" => "id", "type" => "INTEGER" }, { "name" => "name", "type" => "STRING" } ]
    rows = [ [ 1, "alice" ], [ 2, "bob" ] ]

    execution.store_result(schema, rows)
    assert_predicate execution.result_blob, :present?
    assert_not_includes execution.result_blob, "alice"
    inflated = Zlib::Inflate.inflate(execution.result_blob)
    assert_equal({ "schema" => schema, "rows" => rows }, JSON.parse(inflated))
  end

  test "round-trips back to { schema:, rows: } via #result" do
    execution = create_query_execution
    schema = [ { "name" => "id", "type" => "INTEGER" }, { "name" => "name", "type" => "STRING" } ]
    rows = [ [ 1, "alice" ], [ 2, "bob" ] ]

    execution.store_result(schema, rows)
    result = execution.result
    assert_equal schema, result[:schema]
    assert_equal rows, result[:rows]
  end

  test "returns nil from #result when no blob is stored" do
    execution = create_query_execution
    assert_nil execution.result
  end
end
