require "test_helper"

class Admin::SettingsTest < ActionDispatch::IntegrationTest
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
  test "blocks members from the edit form" do
    login_as(member)
    get edit_admin_settings_path
    assert_redirected_to root_path
  end

  test "blocks members from updating the rate" do
    login_as(member)
    patch admin_settings_path, params: { application_setting: { bigquery_yen_per_tb: 1 } }
    assert_redirected_to root_path
    assert_equal 950.0, ApplicationSetting.instance.bigquery_yen_per_tb
  end

  # --- as an admin ---

  # --- GET /admin/settings/edit ---
  test "renders the form with the current rate" do
    login_as(admin)
    get edit_admin_settings_path
    assert_response :ok
    assert_includes response.body, "950"
  end

  # --- PATCH /admin/settings ---
  test "updates the rate" do
    login_as(admin)
    patch admin_settings_path, params: { application_setting: { bigquery_yen_per_tb: 1200.5 } }
    assert_redirected_to edit_admin_settings_path
    assert_equal 1200.5, ApplicationSetting.instance.bigquery_yen_per_tb
  end

  test "re-renders on invalid (negative) input" do
    login_as(admin)
    patch admin_settings_path, params: { application_setting: { bigquery_yen_per_tb: -5 } }
    assert_response :unprocessable_content
    assert_equal 950.0, ApplicationSetting.instance.bigquery_yen_per_tb
  end
end
