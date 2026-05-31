require "rails_helper"

# トピック07（クエリエディタ / CodeMirror 6）のリグレッションテスト。
# CodeMirror 6 は外部CDN（esm.sh）からロードするため js: true（Playwright/chromium）で検証する。
# - 新規クエリ作成画面で `.cm-editor` がマウントされる
# - SQL を入力して保存できる
# - 編集画面で保存済み SQL がエディタに復元される
RSpec.describe "Regression: query editor (topic 07, js)", type: :system, js: true do
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

  it "mounts the CodeMirror editor on the new query form" do
    log_in
    visit new_query_path

    expect(page).to have_css(".cm-editor", wait: 10)
    expect(page).to have_css(".cm-gutters", wait: 10)
  end

  it "lets the user type SQL and save it" do
    log_in
    visit new_query_path
    expect(page).to have_css(".cm-editor", wait: 10)

    fill_in "タイトル", with: "リグレッション入力クエリ"
    select "本番接続", from: "実行先 BigQuery 接続"

    editor = find(".cm-content")
    editor.click
    editor.send_keys("SELECT 1 FROM regression_t")

    click_button "保存"

    expect(page).to have_content("リグレッション入力クエリ", wait: 10)
    saved = user.queries.find_by(title: "リグレッション入力クエリ")
    expect(saved.sql_body).to include("SELECT 1 FROM regression_t")
  end

  it "restores saved SQL into the editor on the edit page" do
    query = create(:query, user: user, title: "復元確認",
                           sql_body: "SELECT restored_column", bigquery_connection: connection)
    log_in
    visit edit_query_path(query)

    expect(page).to have_css(".cm-editor", wait: 10)
    expect(page).to have_css(".cm-content", text: "SELECT restored_column", wait: 10)
  end
end
