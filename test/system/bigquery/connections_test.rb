require "application_system_test_case"

class Bigquery::ConnectionsTest < ApplicationSystemTestCase
  setup do
    @admin = create_user(role: "admin", email: "admin@example.com", password: "password")
  end

  def log_in_as_admin
    visit new_session_path
    fill_in "メールアドレス", with: "admin@example.com"
    fill_in "パスワード", with: "password"
    click_button "ログイン"
  end

  test "lets an admin create, edit, and delete a connection" do
    log_in_as_admin
    visit bigquery_connections_path
    click_link "新規接続"

    fill_in "接続名", with: "本番接続"
    fill_in "プロジェクト ID", with: "my-project-123"
    fill_in "サービスアカウント JSON 鍵", with: '{"type":"service_account","project_id":"my-project-123"}'
    fill_in "コスト上限（GB・任意）", with: "10"
    click_button "作成"

    assert_equal bigquery_connections_path, page.current_path
    assert page.has_content?("本番接続")
    assert page.has_content?("my-project-123")

    assert_equal 10 * (1024**3), Bigquery::Connection.find_by(name: "本番接続").maximum_bytes_billed

    within("tr", text: "本番接続") { click_link "編集" }
    fill_in "接続名", with: "本番接続（改）"
    click_button "更新"

    assert_equal bigquery_connections_path, page.current_path
    assert page.has_content?("本番接続（改）")

    within("tr", text: "本番接続（改）") { click_button "削除" }
    assert page.has_no_content?("本番接続（改）")
  end

  test "does not expose the SA JSON plaintext on the edit screen" do
    secret = "SYSTEM_SPEC_SECRET_KEY"
    connection = create_bigquery_connection(name: "秘匿接続", service_account_json: %({"type":"service_account","private_key":"#{secret}"}))
    log_in_as_admin
    visit edit_bigquery_connection_path(connection)

    assert page.has_no_content?(secret)
  end

  test "does not let a member reach connection management" do
    create_user(role: "member", email: "member@example.com", password: "password")
    visit new_session_path
    fill_in "メールアドレス", with: "member@example.com"
    fill_in "パスワード", with: "password"
    click_button "ログイン"

    visit bigquery_connections_path
    assert_equal root_path, page.current_path
  end
end
