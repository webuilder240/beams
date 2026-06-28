require "application_system_test_case"

# rack_test（JSなし）。グローバルナビ（layouts/application.html.erb）から
# クエリ／ダッシュボードへ到達できることを確認する。
class NavigationTest < ApplicationSystemTestCase
  setup do
    @user = create_user(role: "member", email: "member@example.com", password: "password")
  end

  def log_in
    visit new_session_path
    fill_in "メールアドレス", with: "member@example.com"
    fill_in "パスワード", with: "password"
    click_button "ログイン"
  end

  test "ログイン中はクエリ・ダッシュボードへのリンクをナビに表示する" do
    log_in

    within("nav") do
      assert page.has_link?("クエリ", href: queries_path)
      assert page.has_link?("ダッシュボード", href: dashboards_path)
    end
  end

  test "ナビのクエリリンクからクエリ一覧へ遷移できる" do
    log_in
    within("nav") { click_link "クエリ" }

    assert_equal queries_path, page.current_path
  end

  test "ナビのダッシュボードリンクからダッシュボード一覧へ遷移できる" do
    log_in
    within("nav") { click_link "ダッシュボード" }

    assert_equal dashboards_path, page.current_path
  end

  test "未ログイン時はナビにこれらのリンクを表示しない" do
    visit new_session_path

    within("nav") do
      assert page.has_no_link?("クエリ")
      assert page.has_no_link?("ダッシュボード")
    end
  end
end
