require "rails_helper"

RSpec.describe "初回セットアップウィザード", type: :system do
  let(:valid_json) { '{"type":"service_account","project_id":"my-project-123"}' }

  it "ユーザー 0 件から step1 → step2 → step3 → step4（スキップ）まで通しで完了できる" do
    # step3 の接続テストはスタブ（実 API に繋がない）
    allow_any_instance_of(Bigquery::Connection).to receive(:test_connection)
      .and_return({ success: true })

    # 初回起動: ルートにアクセスすると step1 に誘導される
    visit root_path
    expect(page).to have_current_path(setup_step1_path)

    # step1: 管理者作成
    fill_in "メールアドレス", with: "admin@example.com"
    fill_in "パスワード", with: "password"
    fill_in "パスワード（確認）", with: "password"
    click_button "管理者を作成して次へ"

    expect(page).to have_current_path(setup_step2_path)
    expect(User.find_by(email: "admin@example.com").admin?).to be(true)

    # step2: BigQuery 接続登録
    fill_in "接続名", with: "本番接続"
    fill_in "プロジェクト ID", with: "my-project-123"
    fill_in "サービスアカウント JSON 鍵", with: valid_json
    click_button "接続を登録して次へ"

    expect(page).to have_current_path(setup_step3_path)
    expect(page).to have_content("接続に成功しました")

    # step3 → step4
    click_link "次へ（コスト上限の設定）"
    expect(page).to have_current_path(setup_step4_path)

    # step4: スキップして完了 → ルートへ
    click_button "スキップして完了"
    expect(page).to have_current_path(root_path)
    expect(Bigquery::Connection.first.maximum_bytes_billed).to be_nil

    # 完了後に /setup/step1 へアクセスするとルートに戻される
    visit setup_step1_path
    expect(page).to have_current_path(root_path)
  end

  it "接続テスト失敗時に不足権限が表示される" do
    create(:user, :admin, email: "admin@example.com", password: "password")
    create(:bigquery_connection, name: "本番接続", project_id: "my-project-123")

    allow_any_instance_of(Bigquery::Connection).to receive(:test_connection).and_return(
      { success: false, missing_permissions: [ "bigquery.jobs.create" ], message: "Access Denied" }
    )

    # 完了済み（User 存在）なので、ログインして step3 に直接アクセスする
    visit new_session_path
    fill_in "メールアドレス", with: "admin@example.com"
    fill_in "パスワード", with: "password"
    click_button "ログイン"

    visit setup_step3_path
    expect(page).to have_content("接続に失敗しました")
    expect(page).to have_content("bigquery.jobs.create")
  end
end
