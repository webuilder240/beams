# frozen_string_literal: true

require "test_helper"

class QueriesTest < ActionDispatch::IntegrationTest
  setup do
    @user = create_user(role: "member", password: "password")
    @other_user = create_user(role: "member", password: "password")
    @connection = create_bigquery_connection
  end

  def login_as(who, password: "password")
    post session_path, params: { email: who.email, password: password }
  end

  # --- access control (unauthenticated rejected) ---
  test "redirects to login" do
    create_user # 初回セットアップ誘導を回避
    get queries_path
    assert_redirected_to new_session_path
  end

  # --- as a logged-in user ---

  # --- GET /queries ---
  test "lists all users' queries in updated_at desc order (org full-open §4.9)" do
    login_as(@user)
    old = create_query(user: @user, title: "古い", updated_at: 2.days.ago)
    recent = create_query(user: @user, title: "新しい", updated_at: 1.hour.ago)
    create_query(user: @other_user, title: "他人のクエリ")

    get queries_path
    assert_response :ok
    assert_includes response.body, "新しい"
    assert_includes response.body, "古い"
    # 全ユーザーのクエリが見える（§4.9）
    assert_includes response.body, "他人のクエリ"
    assert response.body.index("新しい") < response.body.index("古い")
  end

  test "filters by title with ?q= (partial match)" do
    login_as(@user)
    create_query(user: @user, title: "売上集計")
    create_query(user: @user, title: "ユーザー一覧")

    get queries_path(q: "売上")
    assert_includes response.body, "売上集計"
    assert_not_includes response.body, "ユーザー一覧"
  end

  test "filters by SQL body with ?q= (partial match, トピック21)" do
    login_as(@user)
    create_query(user: @user, title: "無題クエリA", sql_body: "SELECT user_id FROM events")
    create_query(user: @user, title: "無題クエリB", sql_body: "SELECT name FROM products")

    get queries_path(q: "user_id")
    assert_includes response.body, "無題クエリA"
    assert_not_includes response.body, "無題クエリB"
  end

  # --- GET /queries/new ---
  test "renders the new form" do
    login_as(@user)
    @connection
    get new_query_path
    assert_response :ok
  end

  # --- POST /queries ---
  test "creates a query owned by the current user" do
    login_as(@user)
    before_count = @user.queries.count
    post queries_path, params: {
      query: { title: "新規", sql_body: "SELECT 1", bigquery_connection_id: @connection.id }
    }
    assert_equal before_count + 1, @user.queries.count
    created = @user.queries.find_by(title: "新規")
    assert_equal "SELECT 1", created.sql_body
    assert_equal @connection, created.bigquery_connection
    assert_redirected_to query_path(created)
  end

  test "ignores user_id in params (owner is forced to current_user)" do
    login_as(@user)
    post queries_path, params: {
      query: { title: "強制所有者", sql_body: "SELECT 1", bigquery_connection_id: @connection.id, user_id: @other_user.id }
    }
    created = Query.find_by(title: "強制所有者")
    assert_equal @user, created.user
  end

  test "re-renders on invalid input" do
    login_as(@user)
    before_count = Query.count
    post queries_path, params: {
      query: { title: "", sql_body: "", bigquery_connection_id: @connection.id }
    }
    assert_equal before_count, Query.count
    assert_response :unprocessable_content
  end

  # --- GET /queries/:id ---
  test "shows the current user's query" do
    login_as(@user)
    query = create_query(user: @user, title: "詳細クエリ")
    get query_path(query)
    assert_response :ok
    assert_includes response.body, "詳細クエリ"
  end

  test "shows another user's query (org full-open §4.9)" do
    login_as(@user)
    query = create_query(user: @other_user, title: "他人のクエリ詳細")
    get query_path(query)
    assert_response :ok
    assert_includes response.body, "他人のクエリ詳細"
  end

  test "renders the parameter form for a parameterized query" do
    login_as(@user)
    query = create_query(user: @user, sql_body: "SELECT {{ user_id:number }}")
    get query_path(query)
    assert_includes response.body, "パラメータ"
    assert_includes response.body, "query_params[user_id]"
  end

  test "does not render the parameter form when the query has no parameters" do
    login_as(@user)
    query = create_query(user: @user, sql_body: "SELECT 1")
    get query_path(query)
    assert_not_includes response.body, "query_params["
  end

  test "rejects execution when a required parameter value is blank" do
    login_as(@user)
    query = create_query(user: @user, sql_body: "SELECT {{ a }}, {{ b }}")
    get query_path(query), params: { query_params: { a: "1", b: "" } }
    assert_includes response.body, "未入力のパラメータがあります"
    assert_includes response.body, "b"
  end

  test "ignores parameter names that are not defined on the query (whitelist)" do
    login_as(@user)
    query = create_query(user: @user, sql_body: "SELECT {{ a }}")
    get query_path(query), params: { query_params: { a: "1", evil: "DROP TABLE" } }
    assert_includes response.body, "パラメータを受け付けました"
  end

  test "accepts when all required parameters are present" do
    login_as(@user)
    query = create_query(user: @user, sql_body: "SELECT {{ a }}, {{ b }}")
    get query_path(query), params: { query_params: { a: "1", b: "2" } }
    assert_includes response.body, "パラメータを受け付けました"
  end

  # --- execution history (トピック17) ---
  test "renders the most recent executions newest-first with a result-display link" do
    login_as(@user)
    query = create_query(user: @user, sql_body: "SELECT 1")
    older = create_succeeded_query_execution(query: query, created_at: 2.hours.ago, result_row_count: 1)
    older.store_result([ { "name" => "n", "type" => "INTEGER" } ], [ [ 7 ] ])
    older.save!
    newer = create_failed_query_execution(query: query, created_at: 1.hour.ago, error_message: "boom history")

    get query_path(query)

    assert_response :ok
    # 新しい順で並ぶ（failed が succeeded より前）。各行は dom_id で識別。
    newer_idx = response.body.index("id=\"#{ActionView::RecordIdentifier.dom_id(newer)}\"")
    older_idx = response.body.index("id=\"#{ActionView::RecordIdentifier.dom_id(older)}\"")
    assert newer_idx < older_idx
    assert_includes response.body, "boom history"
    # 成功実行には結果再表示リンクが出る。
    assert_includes response.body, query_execution_path(query, older)
  end

  test "initially renders the latest succeeded result even when a newer execution failed" do
    login_as(@user)
    query = create_query(user: @user, sql_body: "SELECT 1")
    succeeded = create_succeeded_query_execution(query: query, created_at: 2.hours.ago, result_row_count: 1)
    succeeded.store_result([ { "name" => "n", "type" => "INTEGER" } ], [ [ 42 ] ])
    succeeded.save!
    create_failed_query_execution(query: query, created_at: 1.hour.ago, error_message: "later failure")

    get query_path(query)

    # query_result エリアの初期描画は最新の成功結果を優先する
    assert_includes response.body, "42"
  end

  # --- GET /queries/:id/edit ---
  test "renders the edit form for the current user's query" do
    login_as(@user)
    query = create_query(user: @user, sql_body: "SELECT 42")
    get edit_query_path(query)
    assert_response :ok
    assert_includes response.body, "SELECT 42"
  end

  # --- PATCH /queries/:id ---
  test "updates the current user's query" do
    login_as(@user)
    query = create_query(user: @user)
    patch query_path(query), params: {
      query: { title: "更新後", sql_body: "SELECT 2", bigquery_connection_id: @connection.id }
    }
    assert_redirected_to query_path(query)
    assert_equal "更新後", query.reload.title
    assert_equal "SELECT 2", query.sql_body
  end

  test "re-renders on invalid input (update)" do
    login_as(@user)
    query = create_query(user: @user)
    patch query_path(query), params: { query: { title: "" } }
    assert_response :unprocessable_content
  end

  test "updates another user's query (org full-open §4.9)" do
    login_as(@user)
    query = create_query(user: @other_user)
    patch query_path(query), params: {
      query: { title: "更新", sql_body: "SELECT 9", bigquery_connection_id: @connection.id }
    }
    assert_redirected_to query_path(query)
    assert_equal "更新", query.reload.title
  end

  # --- DELETE /queries/:id ---
  test "deletes the current user's query" do
    login_as(@user)
    query = create_query(user: @user)
    before_count = @user.queries.count
    delete query_path(query)
    assert_equal before_count - 1, @user.queries.count
    assert_redirected_to queries_path
  end

  test "deletes another user's query (org full-open §4.9)" do
    login_as(@user)
    query = create_query(user: @other_user)
    before_count = Query.count
    delete query_path(query)
    assert_equal before_count - 1, Query.count
    assert_redirected_to queries_path
  end
end
