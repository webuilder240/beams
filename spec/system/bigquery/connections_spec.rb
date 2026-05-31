require "rails_helper"

RSpec.describe "BigQuery connection management", type: :system do
  let!(:admin) { create(:user, :admin, email: "admin@example.com", password: "password") }

  def log_in_as_admin
    visit new_session_path
    fill_in "メールアドレス", with: "admin@example.com"
    fill_in "パスワード", with: "password"
    click_button "ログイン"
  end

  it "lets an admin create, edit, and delete a connection" do
    log_in_as_admin
    visit bigquery_connections_path
    click_link "新規接続"

    fill_in "接続名", with: "本番接続"
    fill_in "プロジェクト ID", with: "my-project-123"
    fill_in "サービスアカウント JSON 鍵", with: '{"type":"service_account","project_id":"my-project-123"}'
    fill_in "コスト上限（GB・任意）", with: "10"
    click_button "作成"

    expect(page).to have_current_path(bigquery_connections_path)
    expect(page).to have_content("本番接続")
    expect(page).to have_content("my-project-123")

    # GB 入力がバイト換算で保存されている（10 GB = 10 * 1024^3 bytes）
    expect(Bigquery::Connection.find_by(name: "本番接続").maximum_bytes_billed).to eq(10 * (1024**3))

    # 編集
    within("tr", text: "本番接続") { click_link "編集" }
    fill_in "接続名", with: "本番接続（改）"
    click_button "更新"

    expect(page).to have_current_path(bigquery_connections_path)
    expect(page).to have_content("本番接続（改）")

    # 削除
    within("tr", text: "本番接続（改）") { click_button "削除" }
    expect(page).not_to have_content("本番接続（改）")
  end

  it "does not expose the SA JSON plaintext on the edit screen" do
    secret = "SYSTEM_SPEC_SECRET_KEY"
    connection = create(:bigquery_connection, name: "秘匿接続",
      service_account_json: %({"type":"service_account","private_key":"#{secret}"}))
    log_in_as_admin
    visit edit_bigquery_connection_path(connection)

    expect(page).not_to have_content(secret)
  end

  it "does not let a member reach connection management" do
    create(:user, :member, email: "member@example.com", password: "password")
    visit new_session_path
    fill_in "メールアドレス", with: "member@example.com"
    fill_in "パスワード", with: "password"
    click_button "ログイン"

    visit bigquery_connections_path
    expect(page).to have_current_path(root_path)
  end
end
