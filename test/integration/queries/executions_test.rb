# frozen_string_literal: true

require "test_helper"

class Queries::ExecutionsTest < ActionDispatch::IntegrationTest
  setup do
    @user = create_user(role: "member", password: "password")
    @other_user = create_user(role: "member", password: "password")
    @connection = create_bigquery_connection(maximum_bytes_billed: nil)
    @query = create_query(user: @user, bigquery_connection: @connection, sql_body: "SELECT 1")

    # QueryExecutionJob.perform_later をスタブし、呼び出し履歴を記録する。
    @perform_later_calls = []
    calls_ref = @perform_later_calls
    @perform_later_stub = ->(*args) { calls_ref << args; nil }
    QueryExecutionJob.singleton_class.send(:alias_method, :__orig_perform_later, :perform_later)
    QueryExecutionJob.define_singleton_method(:perform_later) { |*args| calls_ref << args; nil }
  end

  teardown do
    QueryExecutionJob.singleton_class.send(:remove_method, :perform_later)
    QueryExecutionJob.singleton_class.send(:alias_method, :perform_later, :__orig_perform_later)
    QueryExecutionJob.singleton_class.send(:remove_method, :__orig_perform_later)
  end

  def login_as(who, password: "password")
    post session_path, params: { email: who.email, password: password }
  end

  # --- access control ---
  test "redirects unauthenticated requests to login" do
    create_user # セットアップ誘導回避
    post query_executions_path(@query)
    assert_redirected_to new_session_path
  end

  test "returns 404 for another user's query" do
    login_as(@user)
    foreign = create_query(user: @other_user, bigquery_connection: @connection)
    post query_executions_path(foreign)
    assert_response :not_found
  end

  # --- as the owner ---
  test "creates a running execution and enqueues the job" do
    login_as(@user)
    before_count = QueryExecution.count
    post query_executions_path(@query)
    assert_equal before_count + 1, QueryExecution.count

    execution = QueryExecution.last
    assert_equal @query, execution.query
    # perform_later(execution, {}) を呼んでいる
    assert(@perform_later_calls.any? { |args| args[0] == execution && args[1] == {} })
    assert_includes [ 303, 201 ], response.status
  end

  # --- with parameters ---
  test "passes whitelisted parameter values to the job" do
    login_as(@user)
    parameterized = create_query(user: @user, bigquery_connection: @connection, sql_body: "SELECT * FROM t WHERE id = {{ id:number }}")

    post query_executions_path(parameterized), params: { query_params: { id: "5" } }

    execution = QueryExecution.last
    assert(@perform_later_calls.any? { |args| args[0] == execution && args[1] == { "id" => "5" } })
  end

  test "does not enqueue or create when a required parameter is missing" do
    login_as(@user)
    parameterized = create_query(user: @user, bigquery_connection: @connection, sql_body: "SELECT * FROM t WHERE id = {{ id:number }}")

    before_count = QueryExecution.count
    before_calls = @perform_later_calls.size
    post query_executions_path(parameterized), params: { query_params: { id: "" } }
    assert_equal before_count, QueryExecution.count

    assert_equal before_calls, @perform_later_calls.size
    assert_response :unprocessable_content
  end

  # --- when at the concurrency limit ---
  test "creates the execution as pending" do
    login_as(@user)
    Queries::ExecutionsController::CONCURRENCY_LIMIT.times { create_running_query_execution(query: @query) }

    post query_executions_path(@query)

    assert_predicate QueryExecution.last, :pending?
    assert_predicate @perform_later_calls.size, :positive?
  end
end
