require "rails_helper"

# rack_test（JSなし）の範囲で dry-run の配線とエンドポイントの結合を確認する。
# 実際の 500ms デバウンス fetch・DOM 更新（Stimulus）は JS 依存のため対象外。
RSpec.describe "Dry run (cost protection)", type: :system do
  let(:user) { create(:user, :member, password: "password") }
  let(:connection) { create(:bigquery_connection, maximum_bytes_billed: nil) }

  def log_in_as(who, password: "password")
    visit new_session_path
    fill_in "メールアドレス", with: who.email
    fill_in "パスワード", with: password
    click_button "ログイン"
  end

  it "wires up the dry-run controller and result/warning areas on the edit page" do
    query = create(:query, user: user, bigquery_connection: connection, sql_body: "SELECT 1")
    log_in_as(user)

    visit edit_query_path(query)

    # dry-run コントローラとエンドポイント URL が配線されている。
    expect(page).to have_css("[data-controller~='dry-run']")
    expect(page).to have_css("[data-dry-run-url-value='#{query_dry_run_path(query)}']")
    # 推定表示エリア・警告バナー・実行ボタン target が存在する。
    expect(page).to have_css("[data-dry-run-target='result']")
    expect(page).to have_css("[data-dry-run-target='warning']", visible: :all)
    expect(page).to have_css("[data-dry-run-target='submit']")
  end

  it "does not enable dry-run on the new (unsaved) query form" do
    connection
    log_in_as(user)

    visit new_query_path

    expect(page).to have_css("[data-controller~='query-editor']")
    expect(page).not_to have_css("[data-controller~='dry-run']")
  end
end
