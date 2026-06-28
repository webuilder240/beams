require "application_system_test_case"

# CodeMirror 6 は外部CDN（esm.sh）からロードするため Playwright/chromium で検証する。
class QueryEditorJsTest < ApplicationJsSystemTestCase
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

  test "mounts the CodeMirror editor and hides the fallback textarea" do
    log_in
    visit new_query_path

    assert page.has_css?(".cm-editor", wait: 10)
    assert page.has_css?(".cm-gutters", wait: 10)
  end

  test "syncs typed SQL into the hidden field and saves it" do
    log_in
    visit new_query_path
    assert page.has_css?(".cm-editor", wait: 10)

    fill_in "タイトル", with: "JS入力クエリ"
    select "本番接続", from: "実行先 BigQuery 接続"

    editor = find(".cm-content")
    editor.click
    editor.send_keys("SELECT 1 FROM t")

    click_button "保存"

    assert page.has_content?("JS入力クエリ", wait: 10)
    saved = @user.queries.find_by(title: "JS入力クエリ")
    assert_includes saved.sql_body, "SELECT 1 FROM t"
  end

  test "loads the saved SQL into the editor on edit" do
    query = create_query(user: @user, title: "既存", sql_body: "SELECT existing_col", bigquery_connection: @connection)
    log_in
    visit edit_query_path(query)

    assert page.has_css?(".cm-editor", wait: 10)
    assert page.has_css?(".cm-content", text: "SELECT existing_col", wait: 10)
  end
end
