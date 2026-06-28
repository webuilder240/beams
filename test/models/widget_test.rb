require "test_helper"

class WidgetTest < ActiveSupport::TestCase
  # --- factory ---
  test "builds a valid widget" do
    assert create_widget.valid?
  end

  # --- associations ---
  test "responds to dashboard" do
    assert_respond_to Widget.new, :dashboard
  end

  test "responds to query" do
    assert_respond_to Widget.new, :query
  end

  test "belongs to a dashboard" do
    dashboard = create_dashboard
    widget = create_widget(dashboard: dashboard)
    assert_equal dashboard, widget.dashboard
  end

  test "belongs to a query" do
    query = create_query
    widget = create_widget(query: query)
    assert_equal query, widget.query
  end

  # --- validations ---
  test "rejects a negative position" do
    assert_not build_widget(position: -1).valid?
  end

  test "rejects a non-integer position" do
    assert_not build_widget(position: 1.5).valid?
  end

  test "accepts a position of 0" do
    assert build_widget(position: 0).valid?
  end

  test "accepts column_span of 1 and 2" do
    assert build_widget(column_span: 1).valid?
    assert build_widget(column_span: 2).valid?
  end

  test "rejects column_span of 3" do
    assert_not build_widget(column_span: 3).valid?
  end

  test "rejects column_span of 0" do
    assert_not build_widget(column_span: 0).valid?
  end

  # --- #display_title ---
  test "returns query.title when title_override is nil" do
    query = create_query(title: "売上クエリ")
    widget = build_widget(query: query, title_override: nil)
    assert_equal "売上クエリ", widget.display_title
  end

  test "returns query.title when title_override is blank" do
    query = create_query(title: "売上クエリ")
    widget = build_widget(query: query, title_override: "")
    assert_equal "売上クエリ", widget.display_title
  end

  test "returns title_override when present" do
    widget = build_widget(title_override: "カスタム名")
    assert_equal "カスタム名", widget.display_title
  end
end
