# frozen_string_literal: true

require "test_helper"

class SchemaCachesTest < ActionDispatch::IntegrationTest
  def login_as(u, password: "password")
    post session_path, params: { email: u.email, password: password }
  end

  # any_instance 相当: クラスに一時的にメソッドを再定義し、ブロック終了後に元へ戻す。
  # impl: 差し替えるメソッド本体（proc/lambda）。nil なら return_value を返すだけ。
  def with_any_instance_stub(klass, method_name, return_value = nil, impl: nil)
    original = klass.instance_method(method_name) if klass.method_defined?(method_name) || klass.private_method_defined?(method_name)
    replacement = impl || ->(*_a, **_k, &_b) { return_value }
    klass.define_method(method_name, &replacement)
    yield
  ensure
    if original
      klass.define_method(method_name, original)
    else
      klass.remove_method(method_name) if klass.method_defined?(method_name, false) || klass.private_method_defined?(method_name, false)
    end
  end

  def stub_sync_value
    { fetched_at: Time.current, datasets: [] }
  end

  # --- POST /schema_caches/refresh when logged in ---
  test "forces a re-sync and redirects back to the schema browser" do
    user = create_user(role: "member", password: "password")
    create_bigquery_connection
    login_as(user)

    with_any_instance_stub(Bigquery::Connection, :sync_schema!, stub_sync_value) do
      post refresh_schema_caches_path

      assert_response :found
      assert_redirected_to schema_browser_path
    end
  end

  test "calls sync_schema! with force: true on the connection" do
    user = create_user(role: "member", password: "password")
    create_bigquery_connection
    login_as(user)

    received_kwargs = nil
    capture = lambda do |*_a, **kwargs, &_b|
      received_kwargs = kwargs
      { fetched_at: Time.current, datasets: [] }
    end

    with_any_instance_stub(Bigquery::Connection, :sync_schema!, impl: capture) do
      post refresh_schema_caches_path
    end

    assert_equal({ force: true }, received_kwargs)
  end

  # --- POST /schema_caches/refresh when not logged in ---
  test "redirects to login" do
    create_user # セットアップ誘導回避
    create_bigquery_connection
    post refresh_schema_caches_path
    assert_redirected_to new_session_path
  end
end
