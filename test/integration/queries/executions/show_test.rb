require "test_helper"

# 過去実行の結果再表示エンドポイント（トピック17）。
# GET /queries/:query_id/executions/:id。トピック13（組織フルオープン）に合わせ、
# 過去結果の再表示（読み取り）は全ユーザー可。実行（create・書き込み/課金）のみ所有者スコープ。
# 存在しない query_id / 当該クエリ配下に存在しない execution id は 404。
class Queries::Executions::ShowTest < ActionDispatch::IntegrationTest
  def user
    @user ||= create_user(role: "member", password: "password")
  end

  def other_user
    @other_user ||= create_user(role: "member", password: "password")
  end

  def connection
    @connection ||= create_bigquery_connection(maximum_bytes_billed: nil)
  end

  def query
    @query ||= create_query(user: user, bigquery_connection: connection, sql_body: "SELECT 1")
  end

  def login_as(who, password: "password")
    post session_path, params: { email: who.email, password: password }
  end

  # --- access control ---
  test "redirects unauthenticated requests to login" do
    create_user # セットアップ誘導回避
    execution = create_succeeded_query_execution(query: query)
    get query_execution_path(query, execution)
    assert_redirected_to new_session_path
  end

  # トピック13（組織フルオープン）に合わせ、過去結果の再表示（読み取り）は
  # 全ユーザー可。実行（create・書き込み/課金）のみ所有者スコープ。
  test "renders another user's query execution result (full-open / トピック13)" do
    login_as(user)
    foreign = create_query(user: other_user, bigquery_connection: connection)
    execution = create_succeeded_query_execution(query: foreign, result_row_count: 1)
    execution.store_result([ { "name" => "shared", "type" => "STRING" } ], [ [ "ok" ] ])
    execution.save!

    get query_execution_path(foreign, execution)

    assert_response :ok
    assert_includes response.body, "shared"
  end

  test "returns 404 for a non-existent query" do
    login_as(user)
    get query_execution_path(query_id: -1, id: 1)
    assert_response :not_found
  end

  test "returns 404 for an execution that does not belong to the query" do
    login_as(user)
    other_query = create_query(user: user, bigquery_connection: connection)
    execution = create_succeeded_query_execution(query: other_query)
    get query_execution_path(query, execution)
    assert_response :not_found
  end

  # --- as the owner ---
  test "renders the result table from the stored blob for a succeeded execution" do
    login_as(user)
    execution = create_succeeded_query_execution(query: query, result_row_count: 2)
    execution.store_result(
      [ { "name" => "id", "type" => "INTEGER" }, { "name" => "name", "type" => "STRING" } ],
      [ [ 1, "alice" ], [ 2, "bob" ] ]
    )
    execution.save!

    get query_execution_path(query, execution)

    assert_response :ok
    assert_includes response.body, "alice"
    assert_includes response.body, "bob"
    assert_includes response.body, "id"
  end

  test "renders the error state for a failed execution" do
    login_as(user)
    execution = create_failed_query_execution(query: query, error_message: "invalid query: boom")
    get query_execution_path(query, execution)
    assert_response :ok
    assert_includes response.body, "invalid query: boom"
  end

  test "renders the running state for a running execution" do
    login_as(user)
    execution = create_running_query_execution(query: query)
    get query_execution_path(query, execution)
    assert_response :ok
    assert_includes response.body, "実行中"
  end
end
