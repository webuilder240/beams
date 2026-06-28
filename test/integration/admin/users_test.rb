require "test_helper"

class Admin::UsersTest < ActionDispatch::IntegrationTest
  def admin
    @admin ||= create_user(role: "admin", password: "password")
  end

  def member
    @member ||= create_user(role: "member", password: "password")
  end

  def login_as(user, password: "password")
    post session_path, params: { email: user.email, password: password }
  end

  # --- access control ---
  test "blocks members from the index" do
    login_as(member)
    get admin_users_path
    assert_redirected_to root_path
  end

  test "blocks members from creating users" do
    login_as(member)
    before_count = User.count
    post admin_users_path, params: { user: { email: "x@example.com", password: "password", role: "member" } }
    assert_equal before_count, User.count
    assert_redirected_to root_path
  end

  # --- as an admin ---

  # --- GET /admin/users ---
  test "lists users" do
    login_as(admin)
    member
    get admin_users_path
    assert_response :ok
    assert_includes response.body, member.email
  end

  # --- GET /admin/users/new ---
  test "renders the new form" do
    login_as(admin)
    get new_admin_user_path
    assert_response :ok
  end

  # --- POST /admin/users ---
  test "creates a user" do
    login_as(admin)
    before_count = User.count
    post admin_users_path, params: {
      user: { email: "new@example.com", password: "password123", role: "admin" }
    }
    assert_equal before_count + 1, User.count
    assert_redirected_to admin_users_path
    created = User.find_by(email: "new@example.com")
    assert_equal "admin", created.role
    assert created.authenticate("password123")
  end

  test "re-renders on invalid input" do
    login_as(admin)
    before_count = User.count
    post admin_users_path, params: { user: { email: "bad", password: "", role: "member" } }
    assert_equal before_count, User.count
    assert_response :unprocessable_content
  end

  # --- GET /admin/users/:id/edit ---
  test "renders the edit form" do
    login_as(admin)
    get edit_admin_user_path(member)
    assert_response :ok
  end

  # --- PATCH /admin/users/:id ---
  test "updates the role without requiring a password" do
    login_as(admin)
    patch admin_user_path(member), params: { user: { role: "admin" } }
    assert_redirected_to admin_users_path
    assert_equal "admin", member.reload.role
  end

  test "re-renders on invalid input (update)" do
    login_as(admin)
    patch admin_user_path(member), params: { user: { email: "" } }
    assert_response :unprocessable_content
    assert_not_equal "", member.reload.email
  end

  # --- DELETE /admin/users/:id ---
  test "deletes the user" do
    login_as(admin)
    target = create_user(role: "member")
    before_count = User.count
    delete admin_user_path(target)
    assert_equal before_count - 1, User.count
    assert_redirected_to admin_users_path
  end

  # --- PATCH /admin/users/:id/reset_password ---
  test "sets a new password the target user can log in with" do
    login_as(admin)
    patch reset_password_admin_user_path(member), params: { user: { password: "brandnew1" } }
    assert_redirected_to admin_users_path
    assert member.reload.authenticate("brandnew1")
  end

  test "re-renders edit on blank password" do
    login_as(admin)
    patch reset_password_admin_user_path(member), params: { user: { password: "" } }
    assert_response :unprocessable_content
  end
end
