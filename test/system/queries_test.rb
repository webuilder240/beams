require "application_system_test_case"

class QueriesTest < ApplicationSystemTestCase
  setup do
    @user = create_user(role: "member", email: "member@example.com", password: "password")
    @connection = create_bigquery_connection(name: "本番接続")
  end

  def log_in
    visit new_session_path
    fill_in "メールアドレス", with: "member@example.com"
    fill_in "パスワード", with: "password"
    click_button "ログイン"
  end

  test "lets a user create, view, and delete a query (rack_test)" do
    log_in
    visit queries_path
    click_link "新規クエリ"

    fill_in "タイトル", with: "売上集計クエリ"
    select "本番接続", from: "実行先 BigQuery 接続"
    fill_in "SQL", with: "SELECT COUNT(*) FROM sales"
    click_button "保存"

    assert page.has_content?("売上集計クエリ")
    assert page.has_content?("SELECT COUNT(*) FROM sales")
    assert page.has_content?("本番接続")

    visit queries_path
    assert page.has_content?("売上集計クエリ")

    within("tr", text: "売上集計クエリ") { click_button "削除" }
    assert_equal queries_path, page.current_path
    assert page.has_no_content?("売上集計クエリ")
  end

  test "edits an existing query and shows the saved SQL in the form (rack_test)" do
    query = create_query(user: @user, title: "編集対象", sql_body: "SELECT 42", bigquery_connection: @connection)
    log_in
    visit edit_query_path(query)

    assert page.has_field?("SQL", with: "SELECT 42")

    fill_in "タイトル", with: "編集済み"
    click_button "更新"

    assert page.has_content?("編集済み")
  end

  test "searches queries by title (rack_test)" do
    create_query(user: @user, title: "売上レポート", bigquery_connection: @connection)
    create_query(user: @user, title: "在庫一覧", bigquery_connection: @connection)
    log_in
    visit queries_path

    fill_in "タイトル/SQL本文で検索", with: "売上"
    click_button "検索"

    assert page.has_content?("売上レポート")
    assert page.has_no_content?("在庫一覧")
  end

  test "searches queries by SQL body (rack_test, トピック21)" do
    create_query(user: @user, title: "Untitled", sql_body: "SELECT user_id FROM events", bigquery_connection: @connection)
    create_query(user: @user, title: "別件", sql_body: "SELECT name FROM products", bigquery_connection: @connection)
    log_in
    visit queries_path

    fill_in "タイトル/SQL本文で検索", with: "user_id"
    click_button "検索"

    assert page.has_content?("Untitled")
    assert page.has_no_content?("別件")
  end

  test "lists all users' queries with owner names (org full-open §4.9, rack_test)" do
    other_user = create_user(role: "member", email: "other@example.com", password: "password")
    create_query(user: @user, title: "自分のクエリ", bigquery_connection: @connection)
    create_query(user: other_user, title: "他人のクエリ", bigquery_connection: @connection)

    log_in
    visit queries_path

    assert page.has_content?("自分のクエリ")
    assert page.has_content?("他人のクエリ")
    assert page.has_content?("member@example.com")
    assert page.has_content?("other@example.com")
  end

  test "guides to connection registration when no connection exists (rack_test)" do
    @connection.destroy
    log_in
    visit new_query_path

    assert page.has_content?("BigQuery 接続がありません")
    assert page.has_link?("BigQuery 接続を登録")
  end

  test "renders the query-editor Stimulus mount on the new form (rack_test)" do
    log_in
    visit new_query_path

    assert page.has_css?("[data-controller='query-editor']")
    assert page.has_css?("[data-query-editor-target='mount']")
  end
end
