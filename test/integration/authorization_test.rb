# frozen_string_literal: true

require "test_helper"

class AuthorizationTest < ActionDispatch::IntegrationTest
  def login_as(user, password: "password")
    post session_path, params: { email: user.email, password: password }
  end

  # --- admin-only endpoints (/admin/users) ---

  # when not logged in
  test "redirects to the login page" do
    create_user # 初回セットアップ誘導を回避（ユーザーが存在する状態）
    get admin_users_path
    assert_redirected_to new_session_path
  end

  # as a member
  test "is redirected to root with an alert" do
    member = create_user(role: "member", password: "password")
    login_as(member)
    get admin_users_path
    assert_redirected_to root_path
    assert_predicate flash[:alert], :present?
  end

  # as an admin
  test "is allowed in" do
    admin = create_user(role: "admin", password: "password")
    login_as(admin)
    get admin_users_path
    assert_response :ok
  end
end
