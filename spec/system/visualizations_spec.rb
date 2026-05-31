require "rails_helper"

RSpec.describe "Visualizations", type: :system do
  let!(:user) { create(:user, :member, email: "member@example.com", password: "password") }

  def log_in
    visit new_session_path
    fill_in "メールアドレス", with: "member@example.com"
    fill_in "パスワード", with: "password"
    click_button "ログイン"
  end

  # 成功実行を結果データ付きで用意する。
  def seed_query_with_result
    query = create(:query, user: user, title: "売上クエリ")
    execution = create(:query_execution, :succeeded, query: query)
    execution.store_result(
      [ { "name" => "day", "type" => "STRING" }, { "name" => "sales", "type" => "INTEGER" } ],
      [ [ "Mon", 10 ], [ "Tue", 20 ], [ "Wed", 30 ] ]
    )
    execution.save!
    query
  end

  describe "table / chart switching (rack_test)" do
    it "shows the result table by default and switches to chart mode" do
      query = seed_query_with_result
      log_in
      visit query_visualization_path(query)

      # デフォルト table モード: 列ヘッダと行が見える
      expect(page).to have_content("day")
      expect(page).to have_content("sales")
      expect(page).to have_content("Mon")

      # チャートタブへ切替
      within("form", text: "チャート") { click_button "チャート" } rescue click_button "チャート"
      expect(page).to have_select("visualization[x_column]")
    end

    it "shows データなし when there is no successful execution" do
      query = create(:query, user: user, title: "未実行クエリ")
      log_in
      visit query_visualization_path(query)
      expect(page).to have_content("データなし")
    end
  end

  describe "axis settings (rack_test)" do
    it "lists the result columns in the axis selects and saves the chart type" do
      query = seed_query_with_result
      query.create_visualization!(display_mode: "chart", chart_type: "line")
      log_in
      visit query_visualization_path(query)

      expect(page).to have_select("visualization[chart_type]")
      x_options = find("select[name='visualization[x_column]']").all("option").map(&:text)
      expect(x_options).to include("day", "sales")

      select "bar", from: "visualization[chart_type]"
      select "day", from: "visualization[x_column]"
      select "sales", from: "visualization[y_columns][]"
      click_button "保存"

      expect(query.reload.visualization.chart_type).to eq("bar")
      expect(query.visualization.x_column).to eq("day")
      expect(query.visualization.y_columns).to eq(%w[sales])
    end
  end

  describe "counter display (rack_test)" do
    it "shows a single aggregated value for the counter chart type" do
      query = seed_query_with_result
      query.create_visualization!(display_mode: "chart", chart_type: "counter",
                                  counter_column: "sales", counter_aggregation: "sum")
      log_in
      visit query_visualization_path(query)

      # sum(sales) = 10 + 20 + 30 = 60
      expect(page).to have_content("60")
      expect(page).to have_content("sum(sales)")
    end
  end

  describe "Chart.js rendering", :js do
    it "renders a canvas for line / bar / pie chart types" do
      query = seed_query_with_result
      viz = query.create_visualization!(display_mode: "chart", chart_type: "line",
                                        x_column: "day", y_columns: %w[sales])
      log_in
      # Turbo のリダイレクト完了を待つ（js: true では非同期）。
      expect(page).to have_content("ログアウト", wait: 10)

      %w[line bar pie].each do |type|
        viz.update!(chart_type: type)
        visit query_visualization_path(query)
        expect(page).to have_css("canvas", wait: 10)
      end
    end
  end
end
