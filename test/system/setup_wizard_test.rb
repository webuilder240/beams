require "application_system_test_case"

class SetupWizardTest < ApplicationSystemTestCase
  VALID_JSON = '{"type":"service_account","project_id":"my-project-123"}'.freeze

  # any_instance スタブの代替: モジュールを prepend して test_connection を上書きする。
  # teardown で巻き戻せないので、各テストで戻り値だけ差し替える方式にする。
  module FakeTestConnection
    def test_connection
      self.class.fake_test_connection_result || super
    end
  end

  setup do
    unless Bigquery::Connection.include?(FakeTestConnection)
      Bigquery::Connection.prepend(FakeTestConnection)
      Bigquery::Connection.singleton_class.attr_accessor :fake_test_connection_result
    end
    Bigquery::Connection.fake_test_connection_result = nil
  end

  teardown do
    Bigquery::Connection.fake_test_connection_result = nil
  end

  test "ユーザー 0 件から step1 → step2 → step3 → step4（スキップ）まで通しで完了できる" do
    Bigquery::Connection.fake_test_connection_result = { success: true }

    # 初回起動: ルートにアクセスすると step1 に誘導される
    visit root_path
    assert_equal setup_step1_path, page.current_path

    # step1: 管理者作成
    fill_in "メールアドレス", with: "admin@example.com"
    fill_in "パスワード", with: "password"
    fill_in "パスワード（確認）", with: "password"
    click_button "管理者を作成して次へ"

    assert_equal setup_step2_path, page.current_path
    assert_equal true, User.find_by(email: "admin@example.com").admin?

    # step2: BigQuery 接続登録
    fill_in "接続名", with: "本番接続"
    fill_in "プロジェクト ID", with: "my-project-123"
    fill_in "サービスアカウント JSON 鍵", with: VALID_JSON
    click_button "接続を登録して次へ"

    assert_equal setup_step3_path, page.current_path
    assert page.has_content?("接続に成功しました")

    # step3 → step4
    click_link "次へ（コスト上限の設定）"
    assert_equal setup_step4_path, page.current_path

    # step4: スキップして完了 → ルートへ
    click_button "スキップして完了"
    assert_equal root_path, page.current_path
    assert_nil Bigquery::Connection.first.maximum_bytes_billed

    # 完了後に /setup/step1 へアクセスするとルートに戻される
    visit setup_step1_path
    assert_equal root_path, page.current_path
  end

  test "接続テスト失敗時に不足権限が表示される" do
    create_user(role: "admin", email: "admin@example.com", password: "password")
    create_bigquery_connection(name: "本番接続", project_id: "my-project-123")

    Bigquery::Connection.fake_test_connection_result = {
      success: false, missing_permissions: [ "bigquery.jobs.create" ], message: "Access Denied"
    }

    # 完了済み（User 存在）なので、ログインして step3 に直接アクセスする
    visit new_session_path
    fill_in "メールアドレス", with: "admin@example.com"
    fill_in "パスワード", with: "password"
    click_button "ログイン"

    visit setup_step3_path
    assert page.has_content?("接続に失敗しました")
    assert page.has_content?("bigquery.jobs.create")
  end
end
