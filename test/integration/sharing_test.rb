# frozen_string_literal: true

require "test_helper"

# 組織フルオープン（計画書 §4.9 / トピック13）。
# ログイン済みユーザーは他ユーザーが作成したクエリ・ダッシュボードを
# 閲覧・編集・削除できる。所有者は記録するが制限には使わない。
class SharingTest < ActionDispatch::IntegrationTest
  setup do
    @owner = create_user(role: "member", password: "password")
    @other = create_user(role: "member", password: "password")
    @connection = create_bigquery_connection
  end

  def login_as(who, password: "password")
    post session_path, params: { email: who.email, password: password }
  end

  # --- Query: 別ユーザーでログイン中 ---
  test "他ユーザーのクエリを閲覧できる" do
    query = create_query(user: @owner, title: "Owner Query")
    login_as(@other)
    get query_path(query)

    assert_response :ok
    assert_includes response.body, "Owner Query"
  end

  test "他ユーザーのクエリを編集できる" do
    query = create_query(user: @owner, title: "Owner Query")
    login_as(@other)
    patch query_path(query), params: {
      query: { title: "Edited By Other", sql_body: "SELECT 2", bigquery_connection_id: @connection.id }
    }

    assert_redirected_to query_path(query)
    assert_equal "Edited By Other", query.reload.title
  end

  test "他ユーザーのクエリを削除できる" do
    query = create_query(user: @owner, title: "Owner Query")
    login_as(@other)
    delete query_path(query)

    assert_redirected_to queries_path
    assert_equal false, Query.exists?(query.id)
  end

  # --- Query: 未ログイン ---
  test "クエリ詳細はログインへリダイレクトされる" do
    query = create_query(user: @owner, title: "Owner Query")
    create_user # 初回セットアップ誘導を回避
    get query_path(query)

    assert_redirected_to new_session_path
  end

  # --- Dashboard: 別ユーザーでログイン中 ---
  test "他ユーザーのダッシュボードを閲覧できる" do
    dashboard = create_dashboard(user: @owner, title: "Owner Dashboard")
    login_as(@other)
    get dashboard_path(dashboard)

    assert_response :ok
    assert_includes response.body, "Owner Dashboard"
  end

  test "他ユーザーのダッシュボードを編集できる" do
    dashboard = create_dashboard(user: @owner, title: "Owner Dashboard")
    login_as(@other)
    patch dashboard_path(dashboard), params: {
      dashboard: { title: "Edited By Other" }
    }

    assert_redirected_to dashboard_path(dashboard)
    assert_equal "Edited By Other", dashboard.reload.title
  end

  test "他ユーザーのダッシュボードを削除できる" do
    dashboard = create_dashboard(user: @owner, title: "Owner Dashboard")
    login_as(@other)
    delete dashboard_path(dashboard)

    assert_redirected_to dashboards_path
    assert_equal false, Dashboard.exists?(dashboard.id)
  end

  # --- Dashboard: 未ログイン ---
  test "ダッシュボード詳細はログインへリダイレクトされる" do
    dashboard = create_dashboard(user: @owner, title: "Owner Dashboard")
    create_user # 初回セットアップ誘導を回避
    get dashboard_path(dashboard)

    assert_redirected_to new_session_path
  end
end
