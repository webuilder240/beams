require "application_system_test_case"

class ParameterizedQueryTest < ApplicationSystemTestCase
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

  test "shows the parameter form on a parameterized query and accepts input (rack_test)" do
    query = create_query(user: @user, title: "パラメータクエリ", sql_body: "SELECT * FROM t WHERE id = {{ user_id:number }}", bigquery_connection: @connection)
    log_in
    visit query_path(query)

    assert page.has_content?("パラメータ")
    assert page.has_field?("user_id")

    fill_in "user_id", with: "42"
    click_button "パラメータを適用"

    assert page.has_content?("パラメータを受け付けました")
  end

  test "rejects submission when a required parameter is left blank (server-side, rack_test)" do
    query = create_query(user: @user, title: "必須パラメータ", sql_body: "SELECT {{ a }}, {{ b }}", bigquery_connection: @connection)
    log_in
    visit query_path(query)

    fill_in "a", with: "1"
    click_button "パラメータを適用"

    assert page.has_content?("未入力のパラメータがあります")
  end

  test "does not show a parameter form for a query without parameters (rack_test)" do
    query = create_query(user: @user, title: "ノーパラメータ", sql_body: "SELECT 1", bigquery_connection: @connection)
    log_in
    visit query_path(query)

    assert_not page.has_content?("パラメータを適用")
  end

  test "renders date and date_range fields for those parameter types (rack_test)" do
    query = create_query(user: @user, title: "日付パラメータ", sql_body: "WHERE d = {{ d:date }} AND c BETWEEN {{ c:date_range }}", bigquery_connection: @connection)
    log_in
    visit query_path(query)

    assert page.has_css?("input#query_param_d[type='date']")
    assert page.has_css?("input#query_param_c_start[type='date']")
    assert page.has_css?("input#query_param_c_end[type='date']")
  end

  test "renders the parameter-form preview container on the edit form (rack_test)" do
    query = create_query(user: @user, sql_body: "SELECT 1", bigquery_connection: @connection)
    log_in
    visit edit_query_path(query)

    assert page.has_css?("[data-controller='parameter-form']")
    assert page.has_css?("[data-parameter-form-target='fields']")
  end
end
