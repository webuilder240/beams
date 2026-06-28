# frozen_string_literal: true

require "test_helper"

class WidgetOrdersTest < ActionDispatch::IntegrationTest
  def login_as(who, password: "password")
    post session_path, params: { email: who.email, password: password }
  end

  def setup_dashboard_with_three_widgets
    user = create_user(role: "member", password: "password")
    dashboard = create_dashboard(user: user)
    query = create_query(user: user)
    w1 = create_widget(dashboard: dashboard, query: query, position: 0)
    w2 = create_widget(dashboard: dashboard, query: query, position: 1)
    w3 = create_widget(dashboard: dashboard, query: query, position: 2)
    [ user, dashboard, query, w1, w2, w3 ]
  end

  # --- PATCH /dashboards/:dashboard_id/widget_order when authenticated ---

  test "(a) reorders widgets and responds with turbo stream" do
    user, dashboard, _query, w1, w2, w3 = setup_dashboard_with_three_widgets
    login_as(user)

    patch dashboard_widget_order_path(dashboard),
          params: { widget_ids: [ w3.id, w1.id, w2.id ] },
          headers: { "Accept" => "text/vnd.turbo-stream.html" }

    assert_response :ok
    assert_equal "text/vnd.turbo-stream.html", response.media_type
    assert_equal 0, w3.reload.position
    assert_equal 1, w1.reload.position
    assert_equal 2, w2.reload.position
  end

  test "(a) redirects to dashboard on HTML fallback" do
    user, dashboard, _query, w1, w2, w3 = setup_dashboard_with_three_widgets
    login_as(user)

    patch dashboard_widget_order_path(dashboard),
          params: { widget_ids: [ w2.id, w1.id, w3.id ] }

    assert_redirected_to dashboard_path(dashboard)
  end

  test "(c) handles empty widget_ids gracefully (returns 2xx, positions unchanged)" do
    user, dashboard, _query, w1, w2, w3 = setup_dashboard_with_three_widgets
    login_as(user)

    original_positions = [ w1.reload.position, w2.reload.position, w3.reload.position ]

    patch dashboard_widget_order_path(dashboard),
          params: { widget_ids: [] },
          headers: { "Accept" => "text/vnd.turbo-stream.html" }

    assert_response :ok
    assert_equal original_positions,
      [ w1.reload.position, w2.reload.position, w3.reload.position ]
  end

  test "(c) handles missing widget_ids param gracefully (returns 2xx)" do
    user, dashboard, _query, _w1, _w2, _w3 = setup_dashboard_with_three_widgets
    login_as(user)

    patch dashboard_widget_order_path(dashboard),
          headers: { "Accept" => "text/vnd.turbo-stream.html" }

    assert_response :ok
  end

  test "(d) ignores widget IDs from other dashboards" do
    user, dashboard, query, w1, w2, _w3 = setup_dashboard_with_three_widgets
    login_as(user)

    other_dashboard = create_dashboard(user: user)
    other_widget = create_widget(dashboard: other_dashboard, query: query, position: 0)

    patch dashboard_widget_order_path(dashboard),
          params: { widget_ids: [ other_widget.id, w1.id, w2.id ] },
          headers: { "Accept" => "text/vnd.turbo-stream.html" }

    assert_response :ok
    assert_equal 0, other_widget.reload.position
  end

  # --- unauthenticated ---
  test "(b) redirects unauthenticated requests to login" do
    _user, dashboard, _query, w1, _w2, _w3 = setup_dashboard_with_three_widgets

    patch dashboard_widget_order_path(dashboard),
          params: { widget_ids: [ w1.id ] }

    assert_redirected_to new_session_path
  end
end
