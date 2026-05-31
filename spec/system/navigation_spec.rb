require "rails_helper"

# rack_test（JSなし）。グローバルナビ（layouts/application.html.erb）から
# クエリ／ダッシュボードへ到達できることを確認する。
RSpec.describe "グローバルナビゲーション", type: :system do
  let!(:user) { create(:user, :member, email: "member@example.com", password: "password") }

  def log_in
    visit new_session_path
    fill_in "メールアドレス", with: "member@example.com"
    fill_in "パスワード", with: "password"
    click_button "ログイン"
  end

  it "ログイン中はクエリ・ダッシュボードへのリンクをナビに表示する" do
    log_in

    within("nav") do
      expect(page).to have_link("クエリ", href: queries_path)
      expect(page).to have_link("ダッシュボード", href: dashboards_path)
    end
  end

  it "ナビのクエリリンクからクエリ一覧へ遷移できる" do
    log_in
    within("nav") { click_link "クエリ" }

    expect(page).to have_current_path(queries_path)
  end

  it "ナビのダッシュボードリンクからダッシュボード一覧へ遷移できる" do
    log_in
    within("nav") { click_link "ダッシュボード" }

    expect(page).to have_current_path(dashboards_path)
  end

  it "未ログイン時はナビにこれらのリンクを表示しない" do
    visit new_session_path

    within("nav") do
      expect(page).to have_no_link("クエリ")
      expect(page).to have_no_link("ダッシュボード")
    end
  end
end
