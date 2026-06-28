require "application_system_test_case"

# トピック07（クエリエディタ / CodeMirror 6）のリグレッションテスト。
class QueryEditorRegressionTest < ApplicationJsSystemTestCase
  setup do
    @user = create_user(role: "member", email: "member@example.com", password: "password")
    @connection = create_bigquery_connection(name: "本番接続")
  end

  def log_in
    visit new_session_path
    fill_in "メールアドレス", with: "member@example.com"
    fill_in "パスワード", with: "password"
    click_button "ログイン"
    assert page.has_content?("ログアウト", wait: 10)
  end

  test "mounts the CodeMirror editor on the new query form" do
    log_in
    visit new_query_path

    assert page.has_css?(".cm-editor", wait: 10)
    assert page.has_css?(".cm-gutters", wait: 10)
  end

  test "lets the user type SQL and save it" do
    log_in
    visit new_query_path
    assert page.has_css?(".cm-editor", wait: 10)

    fill_in "タイトル", with: "リグレッション入力クエリ"
    select "本番接続", from: "実行先 BigQuery 接続"

    editor = find(".cm-content")
    editor.click
    editor.send_keys("SELECT 1 FROM regression_t")

    click_button "保存"

    assert page.has_content?("リグレッション入力クエリ", wait: 10)
    saved = @user.queries.find_by(title: "リグレッション入力クエリ")
    assert_includes saved.sql_body, "SELECT 1 FROM regression_t"
  end

  test "restores saved SQL into the editor on the edit page" do
    query = create_query(user: @user, title: "復元確認", sql_body: "SELECT restored_column", bigquery_connection: @connection)
    log_in
    visit edit_query_path(query)

    assert page.has_css?(".cm-editor", wait: 10)
    assert page.has_css?(".cm-content", text: "SELECT restored_column", wait: 10)
  end
end
