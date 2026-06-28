# frozen_string_literal: true

require "test_helper"

class SchemaBrowsersTest < ActionDispatch::IntegrationTest
  def login_as(u, password: "password")
    post session_path, params: { email: u.email, password: password }
  end

  def schema_structure
    {
      fetched_at: Time.current,
      datasets: [
        {
          dataset_id: "analytics",
          name: "Analytics",
          tables: [
            {
              table_id: "events",
              table_type: "TABLE",
              columns: [
                { column_name: "user_id", data_type: "STRING",
                  is_nullable: true, ordinal_position: 1 }
              ]
            }
          ]
        }
      ]
    }
  end

  # any_instance 相当: クラスに一時的にメソッドを再定義し、ブロック終了後に元へ戻す。
  def with_any_instance_stub(klass, method_name, return_value)
    original = klass.instance_method(method_name) if klass.method_defined?(method_name) || klass.private_method_defined?(method_name)
    klass.define_method(method_name) { |*_a, **_k, &_b| return_value }
    yield
  ensure
    if original
      klass.define_method(method_name, original)
    else
      klass.remove_method(method_name) if klass.method_defined?(method_name, false) || klass.private_method_defined?(method_name, false)
    end
  end

  # --- GET /schema_browser when logged in ---
  test "fetches the cached schema (syncing on first access) and renders the tree" do
    user = create_user(role: "member", password: "password")
    create_bigquery_connection
    login_as(user)

    with_any_instance_stub(Bigquery::Connection, :cached_schema, schema_structure) do
      get schema_browser_path

      assert_response :ok
      assert_includes response.body, "analytics"
      assert_includes response.body, "events"
      assert_includes response.body, "user_id"
    end
  end

  # --- GET /schema_browser when not logged in ---
  test "redirects to login" do
    create_user
    create_bigquery_connection
    get schema_browser_path
    assert_redirected_to new_session_path
  end
end
