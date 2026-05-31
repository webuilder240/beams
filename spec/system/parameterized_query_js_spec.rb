require "rails_helper"

# SQL 編集（CodeMirror）に応じて parameter-form がフィールドを動的に増減する挙動を
# 検証する。エディタは外部CDN・Stimulus 連携を伴うため js: true（Playwright/chromium）。
RSpec.describe "Parameterized query (dynamic form, js)", type: :system, js: true do
  let!(:user) { create(:user, :member, email: "member@example.com", password: "password") }
  let!(:connection) { create(:bigquery_connection, name: "本番接続") }

  def log_in
    visit new_session_path
    fill_in "メールアドレス", with: "member@example.com"
    fill_in "パスワード", with: "password"
    click_button "ログイン"
    expect(page).to have_content("ログアウト", wait: 10)
  end

  it "adds and removes parameter fields as {{ }} placeholders change in the editor" do
    log_in
    visit new_query_path
    expect(page).to have_css(".cm-editor", wait: 10)

    editor = find(".cm-content")
    editor.click
    editor.send_keys("SELECT {{ foo }}")

    # foo フィールドが現れる
    expect(page).to have_css("[data-parameter-form-target='fields'] input[name='query_params[foo]']", wait: 10)

    # 2 つ目のパラメータを追加
    editor.send_keys(", {{ bar:number }}")
    expect(page).to have_css("[data-parameter-form-target='fields'] input[name='query_params[bar]'][type='number']", wait: 10)

    # 全消去するとフィールドも消える
    editor.send_keys([ :control, "a" ], :backspace)
    expect(page).to have_no_css("[data-parameter-form-target='fields'] input", wait: 10)
  end
end
