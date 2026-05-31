require "rails_helper"

RSpec.describe "Dashboards", type: :system do
  let!(:user) { create(:user, :member, email: "member@example.com", password: "password") }

  def log_in
    visit new_session_path
    fill_in "メールアドレス", with: "member@example.com"
    fill_in "パスワード", with: "password"
    click_button "ログイン"
  end

  # 成功実行を結果データ付きで用意したクエリを返す。
  def seed_query_with_result(title:)
    query = create(:query, user: user, title: title)
    execution = create(:query_execution, :succeeded, query: query)
    execution.store_result(
      [ { "name" => "day", "type" => "STRING" }, { "name" => "sales", "type" => "INTEGER" } ],
      [ [ "Mon", 10 ], [ "Tue", 20 ] ]
    )
    execution.save!
    query
  end

  describe "empty state" do
    it "shows a placeholder when there are no dashboards" do
      log_in
      visit dashboards_path
      expect(page).to have_content("まだダッシュボードがありません")
    end
  end

  describe "owner display (org full-open §4.9)" do
    it "lists all users' dashboards with owner names (rack_test)" do
      other_user = create(:user, :member, email: "other@example.com", password: "password")
      create(:dashboard, user: user, title: "自分のD")
      create(:dashboard, user: other_user, title: "他人のD")

      log_in
      visit dashboards_path

      # 全ユーザーのダッシュボードが見える（§4.9）
      expect(page).to have_content("自分のD")
      expect(page).to have_content("他人のD")
      # 所有者名（email）が一覧に表示される
      expect(page).to have_content("member@example.com")
      expect(page).to have_content("other@example.com")
    end
  end

  describe "CRUD and widget flow (rack_test)" do
    it "creates a dashboard, adds widgets, reorders, and deletes" do
      seed_query_with_result(title: "売上クエリ")
      seed_query_with_result(title: "ユーザクエリ")

      log_in

      # ダッシュボード作成
      visit dashboards_path
      click_link "新規作成"
      fill_in "タイトル", with: "経営ダッシュボード"
      fill_in "説明", with: "主要KPI"
      click_button "ダッシュボードを作成する"

      expect(page).to have_content("経営ダッシュボード")
      expect(page).to have_content("まだウィジェットがありません")

      # ウィジェット1（1カラム）
      select "売上クエリ", from: "widget[query_id]"
      select "1カラム", from: "widget[column_span]"
      click_button "ウィジェットを追加"
      expect(page).to have_content("売上クエリ")

      # ウィジェット2（2カラム）
      select "ユーザクエリ", from: "widget[query_id]"
      select "2カラム", from: "widget[column_span]"
      click_button "ウィジェットを追加"
      expect(page).to have_content("ユーザクエリ")

      dashboard = Dashboard.find_by!(title: "経営ダッシュボード")
      expect(dashboard.ordered_widgets.map { |w| w.query.title }).to eq([ "売上クエリ", "ユーザクエリ" ])

      # column_span: 2 のウィジェットは幅広（widget-span-2）
      expect(page).to have_css(".widget-span-2")

      # 「下へ」で 1 番目を下に移動 → 順序入れ替わり
      within(".widget-span-1") { click_button "↓ 下へ" }
      expect(dashboard.reload.ordered_widgets.map { |w| w.query.title }).to eq([ "ユーザクエリ", "売上クエリ" ])

      # リロードしても順序が保持される
      visit dashboard_path(dashboard)
      titles = page.all("article h2").map(&:text)
      expect(titles.first).to include("ユーザクエリ")

      # ウィジェット削除
      expect {
        within(".widget-span-2") { click_button "削除" }
      }.to change { dashboard.reload.widgets.count }.by(-1)

      # ダッシュボード削除（ウィジェットも CASCADE）
      visit dashboards_path
      expect {
        within("li", text: "経営ダッシュボード") { click_button "削除" }
      }.to change(Dashboard, :count).by(-1).and change(Widget, :count).by(-1)
    end

    it "shows 未実行 placeholder for a query without a successful execution" do
      query = create(:query, user: user, title: "未実行クエリ")
      dashboard = create(:dashboard, user: user, title: "プレースホルダD")
      create(:widget, dashboard: dashboard, query: query)

      log_in
      visit dashboard_path(dashboard)
      expect(page).to have_content("未実行")
    end

    it "shows validation errors on invalid create" do
      log_in
      visit new_dashboard_path
      fill_in "タイトル", with: ""
      click_button "ダッシュボードを作成する"
      expect(page).to have_content("タイトル")
      expect(page).to have_css(".bg-red-50")
    end
  end

  describe "widget chart rendering", :js do
    it "renders a canvas for a chart-mode widget" do
      query = seed_query_with_result(title: "チャートクエリ")
      query.create_visualization!(display_mode: "chart", chart_type: "line",
                                  x_column: "day", y_columns: %w[sales])
      dashboard = create(:dashboard, user: user, title: "チャートD")
      create(:widget, dashboard: dashboard, query: query)

      log_in
      expect(page).to have_content("ログアウト", wait: 10)
      visit dashboard_path(dashboard)
      expect(page).to have_css("canvas", wait: 10)
    end
  end
end
