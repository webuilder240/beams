require "application_system_test_case"

# トピック08（コスト保護 dry-run）のリグレッションテスト。
class CostProtectionRegressionTest < ApplicationJsSystemTestCase
  setup do
    @user = create_user(role: "member", email: "member@example.com", password: "password")
  end

  teardown do
    Bigquery::Connection.class_eval do
      if method_defined?(:__orig_dry_run_job)
        alias_method :dry_run_job, :__orig_dry_run_job
        remove_method :__orig_dry_run_job
      end
    end
  end

  def log_in
    visit new_session_path
    fill_in "メールアドレス", with: "member@example.com"
    fill_in "パスワード", with: "password"
    click_button "ログイン"
    assert page.has_content?("ログアウト", wait: 10)
  end

  def stub_dry_run_bytes(bytes)
    job = Struct.new(:bytes_processed).new(bytes)
    Bigquery::Connection.class_eval do
      alias_method :__orig_dry_run_job, :dry_run_job if method_defined?(:dry_run_job) && !method_defined?(:__orig_dry_run_job)
      define_method(:dry_run_job) { |*args, **kwargs| job }
    end
  end

  test "shows the estimated scan size / cost when under the limit" do
    stub_dry_run_bytes(5_000_000_000)
    connection = create_bigquery_connection(name: "上限なし接続", maximum_bytes_billed: nil)
    query = create_query(user: @user, title: "推定表示", sql_body: "SELECT 1", bigquery_connection: connection)
    log_in
    visit edit_query_path(query)

    assert page.has_css?(".cm-editor", wait: 10)

    assert page.has_css?("[data-dry-run-target='result']", text: /推定/, wait: 10)
    assert page.has_css?("[data-dry-run-target='result']", text: /GB/, wait: 10)
    assert page.has_css?("[data-dry-run-target='result']", text: /¥/, wait: 10)

    assert page.has_css?("[data-dry-run-target='warning']", visible: :hidden, wait: 10)
    assert_not page.has_button?("更新", disabled: true)
  end

  test "shows a warning banner and disables the submit button when over the limit" do
    stub_dry_run_bytes(5_000_000_000)
    connection = create_bigquery_connection(name: "上限1GB接続", maximum_bytes_billed: 1_000_000_000)
    query = create_query(user: @user, title: "上限超過", sql_body: "SELECT 1", bigquery_connection: connection)
    log_in
    visit edit_query_path(query)

    assert page.has_css?(".cm-editor", wait: 10)

    assert page.has_css?("[data-dry-run-target='warning']", visible: :visible, wait: 10)
    assert page.has_css?("[data-dry-run-target='warningText']", text: /上限/, wait: 10)

    assert page.has_button?("更新", disabled: true, wait: 10)
  end
end
