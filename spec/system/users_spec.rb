require "rails_helper"

RSpec.describe "User management", type: :system do
  let!(:admin) { create(:user, :admin, email: "admin@example.com", password: "password") }

  def log_in_as_admin
    visit new_session_path
    fill_in "メールアドレス", with: "admin@example.com"
    fill_in "パスワード", with: "password"
    click_button "ログイン"
  end

  it "lets an admin create a new user" do
    log_in_as_admin
    visit admin_users_path
    click_link "新規ユーザー"

    fill_in "メールアドレス", with: "created@example.com"
    fill_in "パスワード", with: "password"
    select "member", from: "ロール"
    click_button "作成"

    expect(page).to have_current_path(admin_users_path)
    expect(page).to have_content("created@example.com")
  end

  it "lets an admin change a user's role" do
    member = create(:user, :member, email: "member@example.com")
    log_in_as_admin
    visit edit_admin_user_path(member)

    select "admin", from: "ロール"
    click_button "更新"

    expect(member.reload.role).to eq("admin")
  end

  it "lets an admin delete a user" do
    create(:user, :member, email: "deleteme@example.com")
    log_in_as_admin
    visit admin_users_path

    expect(page).to have_content("deleteme@example.com")
    within("tr", text: "deleteme@example.com") do
      click_button "削除"
    end

    expect(page).not_to have_content("deleteme@example.com")
  end

  it "does not let a member reach user management" do
    create(:user, :member, email: "plainmember@example.com", password: "password")
    visit new_session_path
    fill_in "メールアドレス", with: "plainmember@example.com"
    fill_in "パスワード", with: "password"
    click_button "ログイン"

    visit admin_users_path
    expect(page).to have_current_path(root_path)
  end
end
