# frozen_string_literal: true

require "test_helper"

class SessionsTest < ActionDispatch::IntegrationTest
  # --- GET /session/new ---
  test "renders the login form" do
    create_user # 初回セットアップ誘導を回避（ユーザーが存在する状態）
    get new_session_path
    assert_response :ok
    assert_includes response.body, "type=\"email\""
    assert_includes response.body, "type=\"password\""
  end

  # --- POST /session with valid credentials ---
  test "logs the user in and redirects" do
    user = create_user(email: "login@example.com", password: "secret123")
    post session_path, params: { email: "login@example.com", password: "secret123" }
    assert_equal user.id, session[:user_id]
    assert_redirected_to root_path
  end

  test "normalizes the submitted email" do
    user = create_user(email: "login@example.com", password: "secret123")
    post session_path, params: { email: "  LOGIN@example.COM ", password: "secret123" }
    assert_equal user.id, session[:user_id]
  end

  # --- POST /session with invalid credentials ---
  test "re-renders the form with an error and no session" do
    create_user(email: "login@example.com", password: "secret123")
    post session_path, params: { email: "login@example.com", password: "wrong" }
    assert_nil session[:user_id]
    assert_response :unprocessable_content
    assert_predicate flash[:alert], :present?
  end

  test "does not log in an unknown email" do
    create_user(email: "login@example.com", password: "secret123")
    post session_path, params: { email: "nobody@example.com", password: "secret123" }
    assert_nil session[:user_id]
    assert_response :unprocessable_content
  end

  # --- DELETE /session ---
  test "logs the user out" do
    user = create_user(password: "secret123")
    post session_path, params: { email: user.email, password: "secret123" }
    assert_equal user.id, session[:user_id]

    delete session_path
    assert_nil session[:user_id]
    assert_redirected_to new_session_path
  end
end
