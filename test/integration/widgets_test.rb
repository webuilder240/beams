# frozen_string_literal: true

require "test_helper"

class WidgetsTest < ActionDispatch::IntegrationTest
  def login_as(who, password: "password")
    post session_path, params: { email: who.email, password: password }
  end

  # --- authentication ---
  test "redirects POST create to login when unauthenticated" do
    create_user
    user = create_user(role: "member", password: "password")
    dashboard = create_dashboard(user: user)
    query = create_query(user: user)

    post dashboard_widgets_path(dashboard), params: { widget: { query_id: query.id } }
    assert_redirected_to new_session_path
  end

  # --- POST /dashboards/:dashboard_id/widgets ---
  test "appends a widget at the tail (max position + 1)" do
    user = create_user(role: "member", password: "password")
    dashboard = create_dashboard(user: user)
    query = create_query(user: user)
    login_as(user)

    create_widget(dashboard: dashboard, query: query, position: 0)

    before_count = dashboard.widgets.count
    post dashboard_widgets_path(dashboard),
         params: { widget: { query_id: query.id, column_span: 2 } }
    assert_equal before_count + 1, dashboard.widgets.count

    widget = dashboard.widgets.order(:position).last
    assert_equal 1, widget.position
    assert_equal 2, widget.column_span
  end

  test "creates the first widget at position 0" do
    user = create_user(role: "member", password: "password")
    dashboard = create_dashboard(user: user)
    query = create_query(user: user)
    login_as(user)

    post dashboard_widgets_path(dashboard), params: { widget: { query_id: query.id } }
    assert_equal 0, dashboard.widgets.order(:position).first.position
  end

  test "responds with a turbo stream" do
    user = create_user(role: "member", password: "password")
    dashboard = create_dashboard(user: user)
    query = create_query(user: user)
    login_as(user)

    post dashboard_widgets_path(dashboard),
         params: { widget: { query_id: query.id } },
         headers: { "Accept" => "text/vnd.turbo-stream.html" }
    assert_equal "text/vnd.turbo-stream.html", response.media_type
  end

  # --- DELETE /dashboards/:dashboard_id/widgets/:id ---
  test "destroys the widget" do
    user = create_user(role: "member", password: "password")
    dashboard = create_dashboard(user: user)
    query = create_query(user: user)
    login_as(user)

    widget = create_widget(dashboard: dashboard, query: query)
    before_count = Widget.count
    delete dashboard_widget_path(dashboard, widget)
    assert_equal before_count - 1, Widget.count
  end
end
