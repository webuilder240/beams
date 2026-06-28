require "securerandom"
require "bcrypt"

# Fixture を補完するためのテストデータヘルパー。
# 1 件きりの共有レコードは spec/fixtures/*.yml を直接参照する（例: users(:member)）。
# 同じ種類のレコードを複数生成したいテストでは、本ヘルパー（build_xxx / create_xxx）を
# 使って fixture と同じ既定属性で新規レコードを作る。
module TestData
  module_function

  def default_service_account_json(project_id = "my-project-#{SecureRandom.hex(2)}")
    {
      type: "service_account",
      project_id: project_id,
      private_key_id: "fixture_private_key_id",
      private_key: "-----BEGIN PRIVATE KEY-----\nFAKE\n-----END PRIVATE KEY-----\n",
      client_email: "sa@#{project_id}.iam.gserviceaccount.com",
      client_id: "123456789012345678901"
    }.to_json
  end

  def build_user(**overrides)
    role = overrides.delete(:role) || "member"
    User.new({
      email: "user_#{SecureRandom.hex(4)}@example.com",
      password: "password",
      role: role
    }.merge(overrides))
  end

  def create_user(**overrides)
    u = build_user(**overrides)
    u.save!
    u
  end

  def build_bigquery_connection(**overrides)
    project_id = overrides[:project_id] || "my-project-#{SecureRandom.hex(2)}"
    Bigquery::Connection.new({
      name: "接続_#{SecureRandom.hex(3)}",
      project_id: project_id,
      service_account_json: default_service_account_json(project_id),
      maximum_bytes_billed: nil
    }.merge(overrides))
  end

  def create_bigquery_connection(**overrides)
    c = build_bigquery_connection(**overrides)
    c.save!
    c
  end

  def build_query(**overrides)
    overrides = overrides.dup
    user = overrides.key?(:user) ? overrides.delete(:user) : create_user
    connection = overrides.key?(:bigquery_connection) ? overrides.delete(:bigquery_connection) : create_bigquery_connection
    Query.new({
      user: user,
      bigquery_connection: connection,
      title: "クエリ_#{SecureRandom.hex(3)}",
      sql_body: "SELECT 1"
    }.merge(overrides))
  end

  def create_query(**overrides)
    q = build_query(**overrides)
    q.save!
    q
  end

  def build_dashboard(**overrides)
    overrides = overrides.dup
    user = overrides.key?(:user) ? overrides.delete(:user) : create_user
    Dashboard.new({
      user: user,
      title: "ダッシュボード_#{SecureRandom.hex(3)}",
      description: nil
    }.merge(overrides))
  end

  def create_dashboard(**overrides)
    d = build_dashboard(**overrides)
    d.save!
    d
  end

  def build_widget(**overrides)
    overrides = overrides.dup
    dashboard = overrides.key?(:dashboard) ? overrides.delete(:dashboard) : create_dashboard
    query = overrides.key?(:query) ? overrides.delete(:query) : create_query
    Widget.new({
      dashboard: dashboard,
      query: query,
      position: 0,
      column_span: 1,
      title_override: nil
    }.merge(overrides))
  end

  def create_widget(**overrides)
    w = build_widget(**overrides)
    w.save!
    w
  end

  def build_visualization(**overrides)
    overrides = overrides.dup
    query = overrides.key?(:query) ? overrides.delete(:query) : create_query
    Visualization.new({
      query: query,
      chart_type: "line",
      display_mode: "table",
      counter_aggregation: "sum"
    }.merge(overrides))
  end

  def create_visualization(**overrides)
    v = build_visualization(**overrides)
    v.save!
    v
  end

  def build_query_execution(**overrides)
    overrides = overrides.dup
    query = overrides.key?(:query) ? overrides.delete(:query) : create_query
    QueryExecution.new({
      query: query,
      status: "pending"
    }.merge(overrides))
  end

  def create_query_execution(**overrides)
    e = build_query_execution(**overrides)
    e.save!
    e
  end

  # 状態プリセット（旧 factory trait 相当）
  def create_succeeded_query_execution(**overrides)
    create_query_execution(**{
      status: "succeeded",
      started_at: 1.minute.ago,
      finished_at: Time.current,
      result_row_count: 1,
      result_truncated: false
    }.merge(overrides))
  end

  def create_failed_query_execution(**overrides)
    create_query_execution(**{
      status: "failed",
      started_at: 1.minute.ago,
      finished_at: Time.current,
      error_message: "boom"
    }.merge(overrides))
  end

  def create_running_query_execution(**overrides)
    create_query_execution(**{
      status: "running",
      started_at: Time.current
    }.merge(overrides))
  end

  def build_query_parameter(**overrides)
    overrides = overrides.dup
    query = overrides.key?(:query) ? overrides.delete(:query) : create_query
    QueryParameter.new({
      query: query,
      name: "param_#{SecureRandom.hex(2)}",
      param_type: "string"
    }.merge(overrides))
  end

  def create_query_parameter(**overrides)
    p = build_query_parameter(**overrides)
    p.save!
    p
  end
end
