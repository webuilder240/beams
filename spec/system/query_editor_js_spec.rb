require "rails_helper"

# CodeMirror 6 は外部CDN（esm.sh）からロードするため js: true（Playwright/chromium）で検証する。
RSpec.describe "Query editor (CodeMirror, js)", type: :system, js: true do
  let!(:user) { create(:user, :member, email: "member@example.com", password: "password") }
  let!(:connection) { create(:bigquery_connection, name: "本番接続") }

  def log_in
    visit new_session_path
    fill_in "メールアドレス", with: "member@example.com"
    fill_in "パスワード", with: "password"
    click_button "ログイン"
    # Turbo のリダイレクト完了を待つ（js: true では非同期）。
    expect(page).to have_content("ログアウト", wait: 10)
  end

  it "mounts the CodeMirror editor and hides the fallback textarea" do
    log_in
    visit new_query_path

    expect(page).to have_css(".cm-editor", wait: 10)
    # 行番号ガターが表示される
    expect(page).to have_css(".cm-gutters", wait: 10)
  end

  it "syncs typed SQL into the hidden field and saves it" do
    log_in
    visit new_query_path
    expect(page).to have_css(".cm-editor", wait: 10)

    fill_in "タイトル", with: "JS入力クエリ"
    select "本番接続", from: "実行先 BigQuery 接続"

    # CodeMirror の編集領域にフォーカスして入力する。
    editor = find(".cm-content")
    editor.click
    editor.send_keys("SELECT 1 FROM t")

    click_button "保存"

    expect(page).to have_content("JS入力クエリ", wait: 10)
    saved = user.queries.find_by(title: "JS入力クエリ")
    expect(saved.sql_body).to include("SELECT 1 FROM t")
  end

  it "loads the saved SQL into the editor on edit" do
    query = create(:query, user: user, title: "既存", sql_body: "SELECT existing_col", bigquery_connection: connection)
    log_in
    visit edit_query_path(query)

    expect(page).to have_css(".cm-editor", wait: 10)
    expect(page).to have_css(".cm-content", text: "SELECT existing_col", wait: 10)
  end
end
