require "test_helper"

class SetupWizardTest < ActionDispatch::IntegrationTest
  def valid_json
    '{"type":"service_account","project_id":"my-project-123"}'
  end

  # --- 初回起動検知（ApplicationController） ---

  # --- when there are no users ---
  test "redirects an arbitrary URL to the setup wizard" do
    get root_path
    assert_redirected_to setup_step1_path
  end

  test "redirects the bigquery connections index to the setup wizard" do
    get bigquery_connections_path
    assert_redirected_to setup_step1_path
  end

  test "does not redirect the wizard itself (no loop)" do
    get setup_step1_path
    assert_response :ok
  end

  # --- when at least one user exists ---
  test "does not redirect to the setup wizard" do
    create_user(role: "admin")
    get new_session_path
    assert_response :ok
  end

  # --- ウィザード完了済みでのリダイレクト ---
  test "redirects /setup to the root" do
    create_user(role: "admin")
    get setup_path
    assert_redirected_to root_path
  end

  test "redirects step1 to the root" do
    create_user(role: "admin")
    get setup_step1_path
    assert_redirected_to root_path
  end

  test "redirects a POST to step1 to the root" do
    create_user(role: "admin")
    post setup_step1_path, params: { user: { email: "x@example.com", password: "password", password_confirmation: "password" } }
    assert_redirected_to root_path
  end

  # --- GET /setup (entry point) ---
  test "redirects to step1 when no users exist" do
    get setup_path
    assert_redirected_to setup_step1_path
  end

  # --- ステップ① admin 作成 ---

  # --- GET /setup/step1 ---
  test "renders the form" do
    get setup_step1_path
    assert_response :ok
  end

  # --- POST /setup/step1 ---
  test "creates an admin user, establishes a session, and advances to step2" do
    before_count = User.count
    post setup_step1_path, params: {
      user: { email: "admin@example.com", password: "password", password_confirmation: "password" }
    }
    assert_equal before_count + 1, User.count

    created = User.find_by(email: "admin@example.com")
    assert_equal true, created.admin?
    assert_equal created.id, session[:user_id]
    assert_redirected_to setup_step2_path
  end

  test "re-renders the form on validation error" do
    before_count = User.count
    post setup_step1_path, params: {
      user: { email: "admin@example.com", password: "password", password_confirmation: "mismatch" }
    }
    assert_equal before_count, User.count
    assert_response :unprocessable_content
  end

  # --- ステップ間の進行制御 ---
  test "redirects step2 back to step1 when no user exists" do
    get setup_step2_path
    assert_redirected_to setup_step1_path
  end

  # --- after step1 is complete (an admin exists and is logged in) ---
  test "allows step2" do
    post setup_step1_path, params: {
      user: { email: "admin@example.com", password: "password", password_confirmation: "password" }
    }
    get setup_step2_path
    assert_response :ok
  end

  test "redirects step3 back to step2 when no connection exists" do
    post setup_step1_path, params: {
      user: { email: "admin@example.com", password: "password", password_confirmation: "password" }
    }
    get setup_step3_path
    assert_redirected_to setup_step2_path
  end

  test "redirects step4 back to step2 when no connection exists" do
    post setup_step1_path, params: {
      user: { email: "admin@example.com", password: "password", password_confirmation: "password" }
    }
    get setup_step4_path
    assert_redirected_to setup_step2_path
  end

  # --- ステップ② 接続登録 ---

  # --- GET /setup/step2 ---
  test "renders the form (step2)" do
    post setup_step1_path, params: {
      user: { email: "admin@example.com", password: "password", password_confirmation: "password" }
    }
    get setup_step2_path
    assert_response :ok
  end

  # --- POST /setup/step2 ---
  test "creates a connection and advances to step3" do
    post setup_step1_path, params: {
      user: { email: "admin@example.com", password: "password", password_confirmation: "password" }
    }
    before_count = Bigquery::Connection.count
    post setup_step2_path, params: {
      bigquery_connection: { name: "本番", project_id: "my-project-123", service_account_json: valid_json }
    }
    assert_equal before_count + 1, Bigquery::Connection.count

    created = Bigquery::Connection.find_by(name: "本番")
    assert_equal "my-project-123", created.project_id
    assert_nil created.maximum_bytes_billed
    assert_redirected_to setup_step3_path
  end

  test "re-renders the form on validation error (step2)" do
    post setup_step1_path, params: {
      user: { email: "admin@example.com", password: "password", password_confirmation: "password" }
    }
    before_count = Bigquery::Connection.count
    post setup_step2_path, params: {
      bigquery_connection: { name: "本番", project_id: "my-project-123", service_account_json: "{not json" }
    }
    assert_equal before_count, Bigquery::Connection.count
    assert_response :unprocessable_content
  end

  # --- ステップ③ 接続テスト ---
  test "shows a success message and a next button when the test passes" do
    post setup_step1_path, params: {
      user: { email: "admin@example.com", password: "password", password_confirmation: "password" }
    }
    post setup_step2_path, params: {
      bigquery_connection: { name: "本番", project_id: "my-project-123", service_account_json: valid_json }
    }
    original = Bigquery::Connection.instance_method(:test_connection)
    Bigquery::Connection.define_method(:test_connection) { { success: true } }
    begin
      get setup_step3_path
      assert_response :ok
      assert_includes response.body, "step4"
    ensure
      Bigquery::Connection.define_method(:test_connection, original)
    end
  end

  test "shows the missing permissions when the test fails" do
    post setup_step1_path, params: {
      user: { email: "admin@example.com", password: "password", password_confirmation: "password" }
    }
    post setup_step2_path, params: {
      bigquery_connection: { name: "本番", project_id: "my-project-123", service_account_json: valid_json }
    }
    original = Bigquery::Connection.instance_method(:test_connection)
    Bigquery::Connection.define_method(:test_connection) do
      { success: false, missing_permissions: [ "bigquery.jobs.create" ], message: "Access Denied" }
    end
    begin
      get setup_step3_path
      assert_response :ok
      assert_includes response.body, "bigquery.jobs.create"
    ensure
      Bigquery::Connection.define_method(:test_connection, original)
    end
  end

  # --- ステップ④ コスト上限 ---

  # --- GET /setup/step4 ---
  test "renders the form (step4)" do
    post setup_step1_path, params: {
      user: { email: "admin@example.com", password: "password", password_confirmation: "password" }
    }
    post setup_step2_path, params: {
      bigquery_connection: { name: "本番", project_id: "my-project-123", service_account_json: valid_json }
    }
    get setup_step4_path
    assert_response :ok
  end

  # --- POST /setup/step4 ---
  test "sets the maximum_bytes_billed and redirects to root" do
    post setup_step1_path, params: {
      user: { email: "admin@example.com", password: "password", password_confirmation: "password" }
    }
    post setup_step2_path, params: {
      bigquery_connection: { name: "本番", project_id: "my-project-123", service_account_json: valid_json }
    }
    post setup_step4_path, params: { bigquery_connection: { maximum_bytes_billed: 5_000_000 } }
    assert_equal 5_000_000, Bigquery::Connection.first.maximum_bytes_billed
    assert_redirected_to root_path
  end

  test "skips and leaves the limit nil when no value is provided" do
    post setup_step1_path, params: {
      user: { email: "admin@example.com", password: "password", password_confirmation: "password" }
    }
    post setup_step2_path, params: {
      bigquery_connection: { name: "本番", project_id: "my-project-123", service_account_json: valid_json }
    }
    post setup_step4_path, params: { bigquery_connection: { maximum_bytes_billed: "" } }
    assert_nil Bigquery::Connection.first.maximum_bytes_billed
    assert_redirected_to root_path
  end
end
