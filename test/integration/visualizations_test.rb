# frozen_string_literal: true

require "test_helper"

class VisualizationsTest < ActionDispatch::IntegrationTest
  setup do
    @user = create_user(role: "member", password: "password")
    @other_user = create_user(role: "member", password: "password")
    @query = create_query(user: @user)
  end

  def login_as(who, password: "password")
    post session_path, params: { email: who.email, password: password }
  end

  # --- GET /queries/:query_id/visualization ---
  test "redirects unauthenticated requests to login (GET)" do
    create_user # セットアップ誘導回避
    get query_visualization_path(@query)
    assert_redirected_to new_session_path
  end

  test "returns 404 for another user's query (GET)" do
    login_as(@user)
    foreign = create_query(user: @other_user)
    get query_visualization_path(foreign)
    assert_response :not_found
  end

  # --- as the owner (GET) ---
  test "renders the visualization page" do
    login_as(@user)
    get query_visualization_path(@query)
    assert_response :ok
  end

  test "builds a default visualization when none exists" do
    login_as(@user)
    get query_visualization_path(@query)
    assert(response.body.include?("チャート") || response.body.include?("テーブル"))
  end

  # --- PATCH /queries/:query_id/visualization ---
  test "redirects unauthenticated requests to login (PATCH)" do
    create_user
    patch query_visualization_path(@query), params: { visualization: { chart_type: "bar" } }
    assert_redirected_to new_session_path
  end

  test "returns 404 for another user's query (PATCH)" do
    login_as(@user)
    foreign = create_query(user: @other_user)
    patch query_visualization_path(foreign), params: { visualization: { chart_type: "bar" } }
    assert_response :not_found
  end

  # --- as the owner (PATCH) ---
  test "creates a visualization on first update (upsert)" do
    login_as(@user)
    before_count = Visualization.count
    patch query_visualization_path(@query),
          params: { visualization: { chart_type: "bar", display_mode: "chart" } }
    assert_equal before_count + 1, Visualization.count

    assert_equal "bar", @query.reload.visualization.chart_type
    assert_equal "chart", @query.visualization.display_mode
  end

  test "updates an existing visualization without creating a new one" do
    login_as(@user)
    create_visualization(query: @query, chart_type: "line")

    before_count = Visualization.count
    patch query_visualization_path(@query),
          params: { visualization: { chart_type: "pie" } }
    assert_equal before_count, Visualization.count

    assert_equal "pie", @query.reload.visualization.chart_type
  end

  test "saves axis settings including y_columns array" do
    login_as(@user)
    patch query_visualization_path(@query),
          params: { visualization: { chart_type: "line", x_column: "day", y_columns: %w[a b] } }

    viz = @query.reload.visualization
    assert_equal "day", viz.x_column
    assert_equal %w[a b], viz.y_columns
  end

  test "saves counter settings" do
    login_as(@user)
    patch query_visualization_path(@query),
          params: { visualization: { chart_type: "counter", counter_column: "amount", counter_aggregation: "avg" } }

    viz = @query.reload.visualization
    assert_equal "counter", viz.chart_type
    assert_equal "amount", viz.counter_column
    assert_equal "avg", viz.counter_aggregation
  end

  test "re-renders the page on invalid input" do
    login_as(@user)
    patch query_visualization_path(@query),
          params: { visualization: { chart_type: "invalid" } }
    assert_response :unprocessable_content
  end
end
