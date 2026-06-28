require "application_system_test_case"

class VisualizationsTest < ApplicationJsSystemTestCase
  setup do
    @user = create_user(role: "member", email: "member@example.com", password: "password")
  end

  def log_in
    visit new_session_path
    fill_in "メールアドレス", with: "member@example.com"
    fill_in "パスワード", with: "password"
    click_button "ログイン"
  end

  def seed_query_with_result
    query = create_query(user: @user, title: "売上クエリ")
    execution = create_succeeded_query_execution(query: query)
    execution.store_result(
      [ { "name" => "day", "type" => "STRING" }, { "name" => "sales", "type" => "INTEGER" } ],
      [ [ "Mon", 10 ], [ "Tue", 20 ], [ "Wed", 30 ] ]
    )
    execution.save!
    query
  end

  # --- table / chart switching (rack_test) ---
  test "shows the result table by default and switches to chart mode" do
    query = seed_query_with_result
    log_in
    visit query_visualization_path(query)

    assert page.has_content?("day")
    assert page.has_content?("sales")
    assert page.has_content?("Mon")

    begin
      within("form", text: "チャート") { click_button "チャート" }
    rescue
      click_button "チャート"
    end
    assert page.has_select?("visualization[x_column]")
  end

  test "shows データなし when there is no successful execution" do
    query = create_query(user: @user, title: "未実行クエリ")
    log_in
    visit query_visualization_path(query)
    assert page.has_content?("データなし")
  end

  # --- axis settings (rack_test) ---
  test "lists the result columns in the axis selects and saves the chart type" do
    query = seed_query_with_result
    query.create_visualization!(display_mode: "chart", chart_type: "line")
    log_in
    visit query_visualization_path(query)

    assert page.has_select?("visualization[chart_type]")
    x_options = find("select[name='visualization[x_column]']").all("option").map(&:text)
    assert_includes x_options, "day"
    assert_includes x_options, "sales"

    select "bar", from: "visualization[chart_type]"
    select "day", from: "visualization[x_column]"
    select "sales", from: "visualization[y_columns][]"
    click_button "保存"

    assert_equal "bar", query.reload.visualization.chart_type
    assert_equal "day", query.visualization.x_column
    assert_equal %w[sales], query.visualization.y_columns
  end

  # --- counter display (rack_test) ---
  test "shows a single aggregated value for the counter chart type" do
    query = seed_query_with_result
    query.create_visualization!(display_mode: "chart", chart_type: "counter",
                                counter_column: "sales", counter_aggregation: "sum")
    log_in
    visit query_visualization_path(query)

    assert page.has_content?("60")
    assert page.has_content?("sum(sales)")
  end

  # --- Chart.js rendering (js) ---
  test "renders a canvas for line / bar / pie chart types" do
    query = seed_query_with_result
    viz = query.create_visualization!(display_mode: "chart", chart_type: "line",
                                      x_column: "day", y_columns: %w[sales])
    log_in
    assert page.has_content?("ログアウト", wait: 10)

    %w[line bar pie].each do |type|
      viz.update!(chart_type: type)
      visit query_visualization_path(query)
      assert page.has_css?("canvas", wait: 10)
    end
  end
end
