require "application_system_test_case"

# SQL 編集（CodeMirror）に応じて parameter-form がフィールドを動的に増減する挙動を
# 検証する。エディタは外部CDN・Stimulus 連携を伴うため Playwright/chromium。
class ParameterizedQueryJsTest < ApplicationJsSystemTestCase
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

  test "adds and removes parameter fields as {{ }} placeholders change in the editor" do
    log_in
    visit new_query_path
    assert page.has_css?(".cm-editor", wait: 10)

    editor = find(".cm-content")
    editor.click
    editor.send_keys("SELECT {{ foo }}")

    assert page.has_css?("[data-parameter-form-target='fields'] input[name='query_params[foo]']", wait: 10)

    editor.send_keys(", {{ bar:number }}")
    assert page.has_css?("[data-parameter-form-target='fields'] input[name='query_params[bar]'][type='number']", wait: 10)

    editor.send_keys([ :control, "a" ], :backspace)
    assert page.has_no_css?("[data-parameter-form-target='fields'] input", wait: 10)
  end
end
