require "rails_helper"

RSpec.describe "Sessions", type: :system do
  let!(:user) { create(:user, email: "user@example.com", password: "password") }

  it "logs in successfully and reaches the dashboard, then logs out" do
    visit new_session_path

    fill_in "メールアドレス", with: "user@example.com"
    fill_in "パスワード", with: "password"
    click_button "ログイン"

    expect(page).to have_current_path(root_path)
    expect(page).to have_content("ダッシュボード")
    expect(page).to have_content("user@example.com")

    click_button "ログアウト"

    expect(page).to have_current_path(new_session_path)
    expect(page).to have_button("ログイン").or have_content("ログイン")
  end

  it "shows an error for invalid credentials" do
    visit new_session_path

    fill_in "メールアドレス", with: "user@example.com"
    fill_in "パスワード", with: "wrong"
    click_button "ログイン"

    expect(page).to have_content("メールアドレスまたはパスワードが正しくありません")
  end

  it "redirects unauthenticated users to the login page" do
    visit root_path
    expect(page).to have_current_path(new_session_path)
  end
end
