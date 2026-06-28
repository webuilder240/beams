require "application_system_test_case"

class UsersTest < ApplicationSystemTestCase
  setup do
    @admin = create_user(role: "admin", email: "admin@example.com", password: "password")
  end

  def log_in_as_admin
    visit new_session_path
    fill_in "メールアドレス", with: "admin@example.com"
    fill_in "パスワード", with: "password"
    click_button "ログイン"
  end

  test "lets an admin create a new user" do
    log_in_as_admin
    visit admin_users_path
    click_link "新規ユーザー"

    fill_in "メールアドレス", with: "created@example.com"
    fill_in "パスワード", with: "password"
    select "member", from: "ロール"
    click_button "作成"

    assert_equal admin_users_path, page.current_path
    assert page.has_content?("created@example.com")
  end

  test "lets an admin change a user's role" do
    member = create_user(role: "member", email: "member@example.com")
    log_in_as_admin
    visit edit_admin_user_path(member)

    select "admin", from: "ロール"
    click_button "更新"

    assert_equal "admin", member.reload.role
  end

  test "lets an admin delete a user" do
    create_user(role: "member", email: "deleteme@example.com")
    log_in_as_admin
    visit admin_users_path

    assert page.has_content?("deleteme@example.com")
    within("tr", text: "deleteme@example.com") do
      click_button "削除"
    end

    assert_not page.has_content?("deleteme@example.com")
  end

  test "does not let a member reach user management" do
    create_user(role: "member", email: "plainmember@example.com", password: "password")
    visit new_session_path
    fill_in "メールアドレス", with: "plainmember@example.com"
    fill_in "パスワード", with: "password"
    click_button "ログイン"

    visit admin_users_path
    assert_equal root_path, page.current_path
  end
end
