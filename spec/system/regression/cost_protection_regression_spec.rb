require "rails_helper"

# トピック08（コスト保護 dry-run / ★目玉機能）のリグレッションテスト。
# 既存の spec/system/dry_run_spec.rb は rack_test のみで配線確認に留まり、
# 「500ms デバウンスの fetch・DOM 更新（Stimulus）」は対象外と明記されている。
# 本ファイルは js: true（Playwright/chromium）でその JS フローを検証する:
# - 上限なし接続 + 5GB → [data-dry-run-target='result'] に「推定 X GB / 約 ¥Y」が表示
# - 上限 1GB 接続 + 5GB スキャン → over_limit で警告バナー表示・実行ボタン disabled
#
# 実 BigQuery API を避けるため Bigquery::Connection#dry_run_job をスタブする。
RSpec.describe "Regression: cost protection dry-run (topic 08, js)", type: :system, js: true do
  let!(:user) { create(:user, :member, email: "member@example.com", password: "password") }

  def log_in
    visit new_session_path
    fill_in "メールアドレス", with: "member@example.com"
    fill_in "パスワード", with: "password"
    click_button "ログイン"
    expect(page).to have_content("ログアウト", wait: 10)
  end

  def stub_dry_run_bytes(bytes)
    job = instance_double("Google::Cloud::Bigquery::QueryJob", bytes_processed: bytes)
    allow_any_instance_of(Bigquery::Connection).to receive(:dry_run_job).and_return(job)
  end

  it "shows the estimated scan size / cost when under the limit" do
    # 上限なし接続 + 5GB スキャン。
    stub_dry_run_bytes(5_000_000_000)
    connection = create(:bigquery_connection, name: "上限なし接続", maximum_bytes_billed: nil)
    query = create(:query, user: user, title: "推定表示", sql_body: "SELECT 1",
                           bigquery_connection: connection)
    log_in
    visit edit_query_path(query)

    expect(page).to have_css(".cm-editor", wait: 10)

    # 初回自動 dry-run（500ms デバウンス）後、推定が result に描画される。
    expect(page).to have_css("[data-dry-run-target='result']", text: /推定/, wait: 10)
    expect(page).to have_css("[data-dry-run-target='result']", text: /GB/, wait: 10)
    expect(page).to have_css("[data-dry-run-target='result']", text: /¥/, wait: 10)

    # 上限超過ではないので警告は出ず、実行ボタンは有効のまま。
    expect(page).to have_css("[data-dry-run-target='warning']", visible: :hidden, wait: 10)
    expect(page).not_to have_button("保存", disabled: true)
  end

  it "shows a warning banner and disables the submit button when over the limit" do
    # 上限 1GB（bytes）接続 + 5GB スキャン → 超過。
    stub_dry_run_bytes(5_000_000_000)
    connection = create(:bigquery_connection, name: "上限1GB接続",
                                              maximum_bytes_billed: 1_000_000_000)
    query = create(:query, user: user, title: "上限超過", sql_body: "SELECT 1",
                           bigquery_connection: connection)
    log_in
    visit edit_query_path(query)

    expect(page).to have_css(".cm-editor", wait: 10)

    # over_limit のとき警告バナーが表示される。
    expect(page).to have_css("[data-dry-run-target='warning']", visible: :visible, wait: 10)
    expect(page).to have_css("[data-dry-run-target='warningText']", text: /上限/, wait: 10)

    # 実行/保存ボタンが disabled になる。
    expect(page).to have_button("保存", disabled: true, wait: 10)
  end
end
