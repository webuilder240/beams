require "test_helper"

class Bigquery::ConnectionsTest < ActionDispatch::IntegrationTest
  def admin
    @admin ||= create_user(role: "admin", password: "password")
  end

  def member
    @member ||= create_user(role: "member", password: "password")
  end

  def valid_json
    '{"type":"service_account","project_id":"my-project-123"}'
  end

  def valid_attributes
    # コスト上限は GB 入力（仮想属性）→ バイト保存。
    { name: "本番", project_id: "my-project-123", service_account_json: valid_json, maximum_bytes_billed_gb: "10" }
  end

  def login_as(user, password: "password")
    post session_path, params: { email: user.email, password: password }
  end

  # --- access control (member rejected) ---
  test "blocks members from the index" do
    login_as(member)
    get bigquery_connections_path
    assert_redirected_to root_path
  end

  test "blocks members from creating connections" do
    login_as(member)
    before_count = Bigquery::Connection.count
    post bigquery_connections_path, params: { bigquery_connection: valid_attributes }
    assert_equal before_count, Bigquery::Connection.count
    assert_redirected_to root_path
  end

  # --- access control (unauthenticated rejected) ---
  test "redirects to login" do
    create_user # 初回セットアップ誘導を回避（ユーザーが存在する状態）
    get bigquery_connections_path
    assert_redirected_to new_session_path
  end

  # --- as an admin ---

  # --- GET /bigquery/connections ---
  test "lists connections without exposing the SA JSON" do
    login_as(admin)
    secret = "TOP_SECRET_KEY_MATERIAL"
    create_bigquery_connection(name: "本番DB", service_account_json: %({"type":"service_account","private_key":"#{secret}"}))
    get bigquery_connections_path
    assert_response :ok
    assert_includes response.body, "本番DB"
    assert_not_includes response.body, secret
  end

  # --- GET /bigquery/connections/new ---
  test "renders the new form" do
    login_as(admin)
    get new_bigquery_connection_path
    assert_response :ok
  end

  # --- POST /bigquery/connections ---
  test "creates a connection" do
    login_as(admin)
    before_count = Bigquery::Connection.count
    post bigquery_connections_path, params: { bigquery_connection: valid_attributes }
    assert_equal before_count + 1, Bigquery::Connection.count
    assert_redirected_to bigquery_connections_path
    created = Bigquery::Connection.find_by(name: "本番")
    assert_equal "my-project-123", created.project_id
    assert_equal valid_json, created.service_account_json
  end

  test "saves the GB cost limit as bytes (10 GB → 10 * 1024^3 bytes)" do
    login_as(admin)
    post bigquery_connections_path, params: { bigquery_connection: valid_attributes }
    created = Bigquery::Connection.find_by(name: "本番")
    assert_equal 10 * (1024**3), created.maximum_bytes_billed
    assert_equal 10.0, created.maximum_bytes_billed_gb
  end

  test "treats a blank GB limit as no limit (nil)" do
    login_as(admin)
    post bigquery_connections_path, params: {
      bigquery_connection: valid_attributes.merge(maximum_bytes_billed_gb: "")
    }
    created = Bigquery::Connection.find_by(name: "本番")
    assert_nil created.maximum_bytes_billed
  end

  test "re-renders on invalid input" do
    login_as(admin)
    before_count = Bigquery::Connection.count
    post bigquery_connections_path, params: {
      bigquery_connection: valid_attributes.merge(service_account_json: "{not json")
    }
    assert_equal before_count, Bigquery::Connection.count
    assert_response :unprocessable_content
  end

  # --- GET /bigquery/connections/:id/edit ---
  test "renders the edit form without exposing the SA JSON plaintext" do
    login_as(admin)
    secret = "EDIT_PAGE_SECRET_KEY"
    connection = create_bigquery_connection(service_account_json: %({"type":"service_account","private_key":"#{secret}"}))
    get edit_bigquery_connection_path(connection)
    assert_response :ok
    assert_not_includes response.body, secret
  end

  # --- PATCH /bigquery/connections/:id ---
  test "updates the name and project_id" do
    login_as(admin)
    connection = create_bigquery_connection
    patch bigquery_connection_path(connection), params: {
      bigquery_connection: { name: "更新後", project_id: "new-project-9", service_account_json: "" }
    }
    assert_redirected_to bigquery_connections_path
    assert_equal "更新後", connection.reload.name
    assert_equal "new-project-9", connection.project_id
  end

  test "keeps the existing SA JSON when the field is left blank" do
    login_as(admin)
    original = '{"type":"service_account","project_id":"keep-me"}'
    connection = create_bigquery_connection(service_account_json: original)
    patch bigquery_connection_path(connection), params: {
      bigquery_connection: { name: "名前だけ変更", service_account_json: "" }
    }
    assert_equal original, connection.reload.service_account_json
  end

  test "replaces the SA JSON when a new value is provided" do
    login_as(admin)
    connection = create_bigquery_connection
    new_json = '{"type":"service_account","project_id":"replaced"}'
    patch bigquery_connection_path(connection), params: {
      bigquery_connection: { service_account_json: new_json }
    }
    assert_equal new_json, connection.reload.service_account_json
  end

  test "re-renders on invalid input (update)" do
    login_as(admin)
    connection = create_bigquery_connection
    patch bigquery_connection_path(connection), params: {
      bigquery_connection: { project_id: "invalid id!" }
    }
    assert_response :unprocessable_content
  end

  # --- DELETE /bigquery/connections/:id ---
  test "deletes the connection" do
    login_as(admin)
    connection = create_bigquery_connection
    before_count = Bigquery::Connection.count
    delete bigquery_connection_path(connection)
    assert_equal before_count - 1, Bigquery::Connection.count
    assert_redirected_to bigquery_connections_path
  end
end
