# frozen_string_literal: true

require "test_helper"

class DashboardsTest < ActionDispatch::IntegrationTest
  setup do
    @user = create_user(role: "member", password: "password")
    @other_user = create_user(role: "member", password: "password")
  end

  def login_as(who, password: "password")
    post session_path, params: { email: who.email, password: password }
  end

  # --- authentication ---
  test "redirects GET /dashboards to login when unauthenticated" do
    create_user # セットアップ誘導回避
    get dashboards_path
    assert_response :found
    assert_redirected_to new_session_path
  end

  test "redirects POST /dashboards to login when unauthenticated" do
    create_user
    post dashboards_path, params: { dashboard: { title: "x" } }
    assert_redirected_to new_session_path
  end

  # --- GET /dashboards ---
  test "lists all dashboards ordered by updated_at desc" do
    login_as(@user)
    old = create_dashboard(user: @user, title: "古い", updated_at: 2.days.ago)
    recent = create_dashboard(user: @other_user, title: "新しい", updated_at: 1.hour.ago)

    get dashboards_path
    assert_response :ok
    assert_includes response.body, "古い"
    # 全ユーザーのダッシュボードが見える（§4.9）
    assert_includes response.body, "新しい"
    assert response.body.index("新しい") < response.body.index("古い")
    assert_predicate old, :present?
    assert_predicate recent, :present?
  end

  test "filters by title partial match with ?q=" do
    login_as(@user)
    create_dashboard(user: @user, title: "売上ダッシュボード")
    create_dashboard(user: @other_user, title: "ユーザー分析")

    get dashboards_path(q: "売上")
    assert_response :ok
    assert_includes response.body, "売上ダッシュボード"
    assert_not_includes response.body, "ユーザー分析"
  end

  test "shows no dashboards when nothing matches ?q=" do
    login_as(@user)
    create_dashboard(user: @user, title: "売上ダッシュボード")

    get dashboards_path(q: "存在しないキーワード")
    assert_response :ok
    assert_not_includes response.body, "売上ダッシュボード"
    assert_includes response.body, "まだダッシュボードがありません"
  end

  test "returns all dashboards when q is blank" do
    login_as(@user)
    create_dashboard(user: @user, title: "売上ダッシュボード")
    create_dashboard(user: @other_user, title: "ユーザー分析")

    get dashboards_path(q: "")
    assert_includes response.body, "売上ダッシュボード"
    assert_includes response.body, "ユーザー分析"
  end

  # --- GET /dashboards/:id ---
  test "shows another user's dashboard (org full-open §4.9)" do
    login_as(@user)
    foreign = create_dashboard(user: @other_user, title: "他人のダッシュボード")
    get dashboard_path(foreign)
    assert_response :ok
    assert_includes response.body, "他人のダッシュボード"
  end

  # --- POST /dashboards ---
  test "creates a dashboard owned by current_user" do
    login_as(@user)
    before_count = Dashboard.count
    post dashboards_path, params: { dashboard: { title: "売上", description: "概要" } }
    assert_equal before_count + 1, Dashboard.count

    dashboard = Dashboard.last
    assert_equal @user, dashboard.user
    assert_equal "売上", dashboard.title
    assert_redirected_to dashboard_path(dashboard)
  end

  test "re-renders new on invalid input" do
    login_as(@user)
    post dashboards_path, params: { dashboard: { title: "" } }
    assert_response :unprocessable_content
  end

  # --- PATCH /dashboards/:id ---
  test "updates another user's dashboard (org full-open §4.9)" do
    login_as(@user)
    foreign = create_dashboard(user: @other_user, title: "旧題")
    patch dashboard_path(foreign), params: { dashboard: { title: "新題" } }
    assert_equal "新題", foreign.reload.title
    assert_redirected_to dashboard_path(foreign)
  end

  test "re-renders edit on invalid input" do
    login_as(@user)
    dashboard = create_dashboard(user: @user)
    patch dashboard_path(dashboard), params: { dashboard: { title: "" } }
    assert_response :unprocessable_content
  end

  # --- DELETE /dashboards/:id ---
  test "destroys the dashboard and its widgets" do
    login_as(@user)
    dashboard = create_dashboard(user: @user)
    create_widget(dashboard: dashboard)

    before_d = Dashboard.count
    before_w = Widget.count
    delete dashboard_path(dashboard)
    assert_equal before_d - 1, Dashboard.count
    assert_equal before_w - 1, Widget.count

    assert_redirected_to dashboards_path
  end
end
