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

  describe "toast notification", :js do
    it "shows a toast message when toast:show event is fired and auto-dismisses" do
      log_in
      expect(page).to have_content("ログアウト", wait: 10)
      visit dashboards_path

      # toast:show カスタムイベントを発火してトーストが表示されることを確認
      page.execute_script(
        "window.dispatchEvent(new CustomEvent('toast:show', { detail: { message: 'テストエラーメッセージ', type: 'error' } }))"
      )

      # 右下にエラートーストが表示される
      expect(page).to have_css("[data-controller='toast']", wait: 5)
      expect(page).to have_content("テストエラーメッセージ", wait: 5)

      # 自動消滅（5秒以内）
      expect(page).not_to have_content("テストエラーメッセージ", wait: 8)
    end
  end

  describe "widget drag-and-drop reorder failure", :js do
    it "restores DOM order and shows error toast when reorder fails" do
      q1 = seed_query_with_result(title: "失敗テスト1番目")
      q2 = seed_query_with_result(title: "失敗テスト2番目")
      dashboard = create(:dashboard, user: user, title: "失敗D&DテストD")
      w1 = create(:widget, dashboard: dashboard, query: q1, position: 0)
      w2 = create(:widget, dashboard: dashboard, query: q2, position: 1)

      log_in
      expect(page).to have_content("ログアウト", wait: 10)
      visit dashboard_path(dashboard)
      expect(page).to have_content("失敗テスト1番目", wait: 10)
      expect(page).to have_content("失敗テスト2番目", wait: 10)
      expect(page).to have_css('[data-sortable-ready="true"]', wait: 10)

      # reorder エンドポイントを 500 でインターセプト（実ドラッグ前に登録）
      page.driver.with_playwright_page do |pw|
        pw.route("**/widgets/reorder", ->(route, _request) {
          route.fulfill(status: 500, contentType: "text/plain", body: "Internal Server Error")
        })
      end

      # 実ポインタ操作で SortableJS（forceFallback: true）に実ドラッグを発火させる
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

      # (a) エラートーストが右下に表示される
      expect(page).to have_css("[data-controller='toast']", wait: 10)
      expect(page).to have_content("並び替えの保存に失敗しました", wait: 10)

      # (b) 並び順がドラッグ前（w1 先頭）に戻る
      expect(page).to have_css(
        ".dashboard-grid > article:first-child h2",
        text: "失敗テスト1番目",
        wait: 10
      )

      # (c) サーバの position は変化していない
      expect(dashboard.reload.ordered_widgets.map { |w| w.query.title })
        .to eq([ "失敗テスト1番目", "失敗テスト2番目" ])
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

      # SortableJS の初期化完了を待つ（connect() で data-sortable-ready="true" が立つ）。
      # 固定 sleep ではなく属性の出現をポーリングすることでフレークを減らす。
      expect(page).to have_css('[data-sortable-ready="true"]', wait: 10)

      # 実ポインタ操作で SortableJS（forceFallback: true）に実ドラッグを発火させる。
      # w1 のドラッグハンドルをつかみ → w2 の位置を通過させて → w2 の下端でドロップ。
      # 中間ステップを挟む（steps:）ことで SortableJS が確実にドラッグを追従する。
      page.driver.with_playwright_page do |pw|
        handle = pw.query_selector("article[data-widget-id='#{w1.id}'] .drag-handle")
        target = pw.query_selector("article[data-widget-id='#{w2.id}']")
        hb = handle.bounding_box
        tb = target.bounding_box

        sx = hb["x"] + hb["width"] / 2
        sy = hb["y"] + hb["height"] / 2
        # w2 の下端付近（中央より下）にドロップして w1 を w2 の後ろへ移動させる
        tx = tb["x"] + tb["width"] / 2
        ty = tb["y"] + tb["height"] - 5

        pw.mouse.move(sx, sy)
        pw.mouse.down
        # ハンドルから少し動かしてドラッグ開始を確実にし、複数ステップで対象まで移動
        pw.mouse.move(sx + 5, sy + 5, steps: 5)
        pw.mouse.move(tx, ty, steps: 15)
        # ドロップ位置で一度静止させて SortableJS の並べ替えを確定させる
        pw.mouse.move(tx, ty, steps: 5)
        pw.mouse.up
      end

      # ドロップ後の PATCH 完了 → Turbo Stream 再描画を、DOM 反映の出現で待つ
      # （固定 sleep を排し、グリッド先頭ウィジェットが「2番目クエリ」になるまでポーリング）。
      expect(page).to have_css(".dashboard-grid > article:first-child h2", text: "2番目クエリ", wait: 10)

      # 実ドラッグの結果としてサーバの position が永続化されていることを確認
      expect(dashboard.reload.ordered_widgets.map { |w| w.query.title }).to eq([ "2番目クエリ", "1番目クエリ" ])

      # リロード後も順序が保持される
      visit dashboard_path(dashboard)
      titles = page.all("article h2", wait: 10).map(&:text)
      expect(titles.first).to include("2番目クエリ")
      expect(titles.last).to include("1番目クエリ")
    end
  end
end
