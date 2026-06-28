require "application_system_test_case"

class DashboardsTest < ApplicationSystemTestCase
  setup do
    @user = create_user(role: "member", email: "member@example.com", password: "password")
  end

  def log_in
    visit new_session_path
    fill_in "メールアドレス", with: "member@example.com"
    fill_in "パスワード", with: "password"
    click_button "ログイン"
  end

  # 成功実行を結果データ付きで用意したクエリを返す。
  def seed_query_with_result(title:)
    query = create_query(user: @user, title: title)
    execution = create_succeeded_query_execution(query: query)
    execution.store_result(
      [ { "name" => "day", "type" => "STRING" }, { "name" => "sales", "type" => "INTEGER" } ],
      [ [ "Mon", 10 ], [ "Tue", 20 ] ]
    )
    execution.save!
    query
  end

  # --- empty state ---
  test "shows a placeholder when there are no dashboards" do
    log_in
    visit dashboards_path
    assert page.has_content?("まだダッシュボードがありません")
  end

  # --- owner display (org full-open §4.9) ---
  test "lists all users' dashboards with owner names (rack_test)" do
    other_user = create_user(role: "member", email: "other@example.com", password: "password")
    create_dashboard(user: @user, title: "自分のD")
    create_dashboard(user: other_user, title: "他人のD")

    log_in
    visit dashboards_path

    assert page.has_content?("自分のD")
    assert page.has_content?("他人のD")
    assert page.has_content?("member@example.com")
    assert page.has_content?("other@example.com")
  end

  # --- title search (rack_test) ---
  test "filters the list by entering a keyword in the search form" do
    create_dashboard(user: @user, title: "売上ダッシュボード")
    create_dashboard(user: @user, title: "ユーザー分析")

    log_in
    visit dashboards_path

    assert page.has_content?("売上ダッシュボード")
    assert page.has_content?("ユーザー分析")

    fill_in "q", with: "売上"
    click_button "検索"

    assert page.has_content?("売上ダッシュボード")
    assert page.has_no_content?("ユーザー分析")
    assert page.has_field?("q", with: "売上")
  end

  # --- CRUD and widget flow (rack_test) ---
  test "creates a dashboard, adds widgets, and deletes" do
    seed_query_with_result(title: "売上クエリ")
    seed_query_with_result(title: "ユーザクエリ")

    log_in

    visit dashboards_path
    click_link "新規作成"
    fill_in "タイトル", with: "経営ダッシュボード"
    fill_in "説明", with: "主要KPI"
    click_button "ダッシュボードを作成する"

    assert page.has_content?("経営ダッシュボード")
    assert page.has_content?("まだウィジェットがありません")

    select "売上クエリ", from: "widget[query_id]"
    select "1カラム", from: "widget[column_span]"
    click_button "ウィジェットを追加"
    assert page.has_content?("売上クエリ")

    select "ユーザクエリ", from: "widget[query_id]"
    select "2カラム", from: "widget[column_span]"
    click_button "ウィジェットを追加"
    assert page.has_content?("ユーザクエリ")

    dashboard = Dashboard.find_by!(title: "経営ダッシュボード")
    assert_equal [ "売上クエリ", "ユーザクエリ" ], dashboard.ordered_widgets.map { |w| w.query.title }

    assert page.has_css?(".widget-span-2")

    before_count = dashboard.reload.widgets.count
    within(".widget-span-2") { click_button "削除" }
    assert_equal before_count - 1, dashboard.reload.widgets.count

    visit dashboards_path
    dashboards_before = Dashboard.count
    widgets_before = Widget.count
    within("li", text: "経営ダッシュボード") { click_button "削除" }
    assert_equal dashboards_before - 1, Dashboard.count
    assert_equal widgets_before - 1, Widget.count
  end

  test "shows 未実行 placeholder for a query without a successful execution" do
    query = create_query(user: @user, title: "未実行クエリ")
    dashboard = create_dashboard(user: @user, title: "プレースホルダD")
    create_widget(dashboard: dashboard, query: query)

    log_in
    visit dashboard_path(dashboard)
    assert page.has_content?("未実行")
  end

  test "shows validation errors on invalid create" do
    log_in
    visit new_dashboard_path
    fill_in "タイトル", with: ""
    click_button "ダッシュボードを作成する"
    assert page.has_content?("タイトル")
    assert page.has_css?(".bg-red-50")
  end

  # --- widget query link (turbo frame escape) ---
  test "breaks the widget title link out of the widgets turbo frame" do
    query = seed_query_with_result(title: "売上クエリ")
    dashboard = create_dashboard(user: @user, title: "売上D")
    create_widget(dashboard: dashboard, query: query, position: 0, column_span: 1)

    log_in
    visit dashboard_path(dashboard)

    assert page.has_css?(
      "a[href='#{query_path(query)}'][data-turbo-frame='_top']", text: "売上クエリ"
    )
  end

  # --- widget chart rendering (js) ---
  test "renders a canvas for a chart-mode widget" do
    query = seed_query_with_result(title: "チャートクエリ")
    query.create_visualization!(display_mode: "chart", chart_type: "line",
                                x_column: "day", y_columns: %w[sales])
    dashboard = create_dashboard(user: @user, title: "チャートD")
    create_widget(dashboard: dashboard, query: query)

    log_in
    assert page.has_content?("ログアウト", wait: 10)
    visit dashboard_path(dashboard)
    assert page.has_css?("canvas", wait: 10)
  end

  # --- toast notification (js) ---
  test "shows a toast message when toast:show event is fired and auto-dismisses" do
    log_in
    assert page.has_content?("ログアウト", wait: 10)
    visit dashboards_path

    page.execute_script(
      "window.dispatchEvent(new CustomEvent('toast:show', { detail: { message: 'テストエラーメッセージ', type: 'error' } }))"
    )

    assert page.has_css?("[data-controller='toast']", wait: 5)
    assert page.has_content?("テストエラーメッセージ", wait: 5)

    assert page.has_no_content?("テストエラーメッセージ", wait: 8)
  end

  # --- widget drag-and-drop reorder failure (js) ---
  test "restores DOM order and shows error toast when reorder fails" do
    q1 = seed_query_with_result(title: "失敗テスト1番目")
    q2 = seed_query_with_result(title: "失敗テスト2番目")
    dashboard = create_dashboard(user: @user, title: "失敗D&DテストD")
    w1 = create_widget(dashboard: dashboard, query: q1, position: 0)
    w2 = create_widget(dashboard: dashboard, query: q2, position: 1)

    log_in
    assert page.has_content?("ログアウト", wait: 10)
    visit dashboard_path(dashboard)
    assert page.has_content?("失敗テスト1番目", wait: 10)
    assert page.has_content?("失敗テスト2番目", wait: 10)
    assert page.has_css?('[data-sortable-ready="true"]', wait: 10)

    page.driver.with_playwright_page do |pw|
      pw.route("**/widget_order", ->(route, _request) {
        route.fulfill(status: 500, contentType: "text/plain", body: "Internal Server Error")
      })
    end

    page.driver.with_playwright_page do |pw|
      handle = pw.query_selector("article[data-widget-id='#{w1.id}'] .drag-handle")
      target = pw.query_selector("article[data-widget-id='#{w2.id}']")
      hb = handle.bounding_box
      tb = target.bounding_box

      sx = hb["x"] + hb["width"] / 2
      sy = hb["y"] + hb["height"] / 2
      tx = tb["x"] + tb["width"] / 2
      ty = tb["y"] + tb["height"] - 5

      pw.mouse.move(sx, sy)
      pw.mouse.down
      pw.mouse.move(sx + 5, sy + 5, steps: 5)
      pw.mouse.move(tx, ty, steps: 15)
      pw.mouse.move(tx, ty, steps: 5)
      pw.mouse.up
    end

    assert page.has_css?("[data-controller='toast']", wait: 10)
    assert page.has_content?("並び替えの保存に失敗しました", wait: 10)

    assert page.has_css?(
      ".dashboard-grid > article:first-child h2",
      text: "失敗テスト1番目",
      wait: 10
    )

    assert_equal [ "失敗テスト1番目", "失敗テスト2番目" ],
                 dashboard.reload.ordered_widgets.map { |w| w.query.title }
  end

  # --- widget drag-and-drop reorder (js) ---
  test "reorders widgets by drag-and-drop and persists position" do
    q1 = seed_query_with_result(title: "1番目クエリ")
    q2 = seed_query_with_result(title: "2番目クエリ")
    dashboard = create_dashboard(user: @user, title: "D&DテストD")
    w1 = create_widget(dashboard: dashboard, query: q1, position: 0)
    w2 = create_widget(dashboard: dashboard, query: q2, position: 1)

    log_in
    assert page.has_content?("ログアウト", wait: 10)
    visit dashboard_path(dashboard)
    assert page.has_content?("1番目クエリ", wait: 10)
    assert page.has_content?("2番目クエリ", wait: 10)

    assert page.has_css?('[data-sortable-ready="true"]', wait: 10)

    page.driver.with_playwright_page do |pw|
      handle = pw.query_selector("article[data-widget-id='#{w1.id}'] .drag-handle")
      target = pw.query_selector("article[data-widget-id='#{w2.id}']")
      hb = handle.bounding_box
      tb = target.bounding_box

      sx = hb["x"] + hb["width"] / 2
      sy = hb["y"] + hb["height"] / 2
      tx = tb["x"] + tb["width"] / 2
      ty = tb["y"] + tb["height"] - 5

      pw.mouse.move(sx, sy)
      pw.mouse.down
      pw.mouse.move(sx + 5, sy + 5, steps: 5)
      pw.mouse.move(tx, ty, steps: 15)
      pw.mouse.move(tx, ty, steps: 5)
      pw.mouse.up
    end

    assert page.has_css?(".dashboard-grid > article:first-child h2", text: "2番目クエリ", wait: 10)

    assert_equal [ "2番目クエリ", "1番目クエリ" ],
                 dashboard.reload.ordered_widgets.map { |w| w.query.title }

    visit dashboard_path(dashboard)
    titles = page.all("article h2", wait: 10).map(&:text)
    assert_includes titles.first, "2番目クエリ"
    assert_includes titles.last, "1番目クエリ"
  end
end
