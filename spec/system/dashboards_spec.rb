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

  describe "title search (rack_test)" do
    it "filters the list by entering a keyword in the search form" do
      create(:dashboard, user: user, title: "売上ダッシュボード")
      create(:dashboard, user: user, title: "ユーザー分析")

      log_in
      visit dashboards_path

      expect(page).to have_content("売上ダッシュボード")
      expect(page).to have_content("ユーザー分析")

      fill_in "q", with: "売上"
      click_button "検索"

      expect(page).to have_content("売上ダッシュボード")
      expect(page).not_to have_content("ユーザー分析")
      # キーワードが入力欄に残る
      expect(page).to have_field("q", with: "売上")
    end
  end

  describe "CRUD and widget flow (rack_test)" do
    it "creates a dashboard, adds widgets, and deletes" do
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

  describe "widget query link (turbo frame escape)" do
    # ウィジェットは turbo_frame "widgets" 内に描画される。クエリ詳細へのリンクが
    # frame を抜けないと、遷移先 queries/show に同名 frame が無く Turbo が
    # 「Content missing」を表示する。data-turbo-frame="_top" の付与を担保する。
    it "breaks the widget title link out of the widgets turbo frame" do
      query = seed_query_with_result(title: "売上クエリ")
      dashboard = create(:dashboard, user: user, title: "売上D")
      create(:widget, dashboard: dashboard, query: query, position: 0, column_span: 1)

      log_in
      visit dashboard_path(dashboard)

      expect(page).to have_css(
        "a[href='#{query_path(query)}'][data-turbo-frame='_top']", text: "売上クエリ"
      )
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

  describe "widget drag-and-drop reorder", :js do
    it "reorders widgets by drag-and-drop and persists position" do
      q1 = seed_query_with_result(title: "1番目クエリ")
      q2 = seed_query_with_result(title: "2番目クエリ")
      dashboard = create(:dashboard, user: user, title: "D&DテストD")
      w1 = create(:widget, dashboard: dashboard, query: q1, position: 0)
      w2 = create(:widget, dashboard: dashboard, query: q2, position: 1)

      log_in
      expect(page).to have_content("ログアウト", wait: 10)
      visit dashboard_path(dashboard)
      expect(page).to have_content("1番目クエリ", wait: 10)
      expect(page).to have_content("2番目クエリ", wait: 10)

      # SortableJS はポインタイベントを使うため Playwright の手動マウス操作で D&D を行う
      # w1 (1番目) を w2 (2番目) の下へドラッグ
      source = find("article[data-widget-id='#{w1.id}'] .drag-handle")
      target = find("article[data-widget-id='#{w2.id}']")

      source_pos = source.native.bounding_box
      target_pos = target.native.bounding_box

      page.driver.browser.mouse.move(
        x: (source_pos["x"] + source_pos["width"] / 2).to_i,
        y: (source_pos["y"] + source_pos["height"] / 2).to_i
      )
      page.driver.browser.mouse.down
      sleep 0.3

      # ターゲット要素の下端付近にドロップ
      page.driver.browser.mouse.move(
        x: (target_pos["x"] + target_pos["width"] / 2).to_i,
        y: (target_pos["y"] + target_pos["height"] - 5).to_i
      )
      sleep 0.3
      page.driver.browser.mouse.up
      sleep 1.0

      # position が更新されリロード後も保持されることを確認
      visit dashboard_path(dashboard)
      titles = page.all("article h2", wait: 10).map(&:text)
      expect(titles.first).to include("2番目クエリ")
      expect(titles.last).to include("1番目クエリ")

      expect(dashboard.reload.ordered_widgets.map { |w| w.query.title }).to eq([ "2番目クエリ", "1番目クエリ" ])
    end
  end
end
