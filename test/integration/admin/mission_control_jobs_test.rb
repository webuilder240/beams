require "test_helper"

class Admin::MissionControlJobsTest < ActionDispatch::IntegrationTest
  def admin
    @admin ||= create_user(role: "admin", password: "password")
  end

  def member
    @member ||= create_user(role: "member", password: "password")
  end

  def login_as(user, password: "password")
    post session_path, params: { email: user.email, password: password }
  end

  # --- GET /jobs ---
  test "redirects unauthenticated users to login" do
    admin # User を 1 件以上作って setup ウィザードへの誘導を回避する
    get "/jobs"
    assert_redirected_to "/session/new"
  end

  test "blocks non-admin members" do
    login_as(member)
    get "/jobs"
    assert_redirected_to "/"
  end

  test "allows admin to access the Mission Control dashboard" do
    login_as(admin)
    get "/jobs"
    assert_response :ok
  end
end
