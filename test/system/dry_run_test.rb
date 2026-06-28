require "application_system_test_case"

# rack_test（JSなし）の範囲で dry-run の配線とエンドポイントの結合を確認する。
# 実際の 500ms デバウンス fetch・DOM 更新（Stimulus）は JS 依存のため対象外。
class DryRunTest < ApplicationSystemTestCase
  def log_in_as(who, password: "password")
    visit new_session_path
    fill_in "メールアドレス", with: who.email
    fill_in "パスワード", with: password
    click_button "ログイン"
  end

  test "wires up the dry-run controller and result/warning areas on the edit page" do
    user = create_user(role: "member", password: "password")
    connection = create_bigquery_connection(maximum_bytes_billed: nil)
    query = create_query(user: user, bigquery_connection: connection, sql_body: "SELECT 1")
    log_in_as(user)

    visit edit_query_path(query)

    # dry-run コントローラとエンドポイント URL が配線されている。
    assert page.has_css?("[data-controller~='dry-run']")
    assert page.has_css?("[data-dry-run-url-value='#{query_dry_run_path(query)}']")
    # 推定表示エリア・警告バナー・実行ボタン target が存在する。
    assert page.has_css?("[data-dry-run-target='result']")
    assert page.has_css?("[data-dry-run-target='warning']", visible: :all)
    assert page.has_css?("[data-dry-run-target='submit']")
  end

  test "does not enable dry-run on the new (unsaved) query form" do
    user = create_user(role: "member", password: "password")
    create_bigquery_connection(maximum_bytes_billed: nil)
    log_in_as(user)

    visit new_query_path

    assert page.has_css?("[data-controller~='query-editor']")
    assert page.has_no_css?("[data-controller~='dry-run']")
  end
end
