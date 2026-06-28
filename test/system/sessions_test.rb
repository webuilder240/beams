require "application_system_test_case"

class SessionsTest < ApplicationSystemTestCase
  setup do
    @user = create_user(email: "user@example.com", password: "password")
  end

  test "logs in successfully and reaches the dashboard, then logs out" do
    visit new_session_path

    fill_in "メールアドレス", with: "user@example.com"
    fill_in "パスワード", with: "password"
    click_button "ログイン"

    assert_equal root_path, page.current_path
    assert page.has_content?("ダッシュボード")
    assert page.has_content?("user@example.com")

    click_button "ログアウト"

    assert_equal new_session_path, page.current_path
    assert(page.has_button?("ログイン") || page.has_content?("ログイン"))
  end

  test "shows an error for invalid credentials" do
    visit new_session_path

    fill_in "メールアドレス", with: "user@example.com"
    fill_in "パスワード", with: "wrong"
    click_button "ログイン"

    assert page.has_content?("メールアドレスまたはパスワードが正しくありません")
  end

  test "redirects unauthenticated users to the login page" do
    visit root_path
    assert_equal new_session_path, page.current_path
  end
end
