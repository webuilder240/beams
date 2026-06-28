require "application_system_test_case"

# トピック06（スキーマブラウザ）× 07（クエリエディタ）結合のリグレッションテスト。
class SchemaBrowserInsertionRegressionTest < ApplicationJsSystemTestCase
  setup do
    @user = create_user(role: "member", email: "member@example.com", password: "password")
    @connection = create_bigquery_connection(name: "本番接続")

    schema_structure = {
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
                { column_name: "user_id", data_type: "STRING", is_nullable: true, ordinal_position: 1 }
              ]
            }
          ]
        }
      ]
    }

    connection_id = @connection.id
    original_exist = Rails.cache.method(:exist?)
    Rails.cache.define_singleton_method(:exist?) do |*args|
      if args.first == "bigquery:schema:#{connection_id}"
        true
      else
        original_exist.call(*args)
      end
    end
    @restore_cache = -> {
      Rails.cache.singleton_class.send(:remove_method, :exist?) if Rails.cache.singleton_class.method_defined?(:exist?, false)
    }

    Bigquery::Connection.class_eval do
      alias_method :__orig_cached_schema, :cached_schema if method_defined?(:cached_schema) && !method_defined?(:__orig_cached_schema)
      define_method(:cached_schema) { schema_structure }
    end
    @restore_cached_schema = -> {
      Bigquery::Connection.class_eval do
        if method_defined?(:__orig_cached_schema)
          alias_method :cached_schema, :__orig_cached_schema
          remove_method :__orig_cached_schema
        end
      end
    }
  end

  teardown do
    @restore_cached_schema&.call
    @restore_cache&.call
  end

  def log_in
    visit new_session_path
    fill_in "メールアドレス", with: "member@example.com"
    fill_in "パスワード", with: "password"
    click_button "ログイン"
    assert page.has_content?("ログアウト", wait: 10)
  end

  test "inserts a column name into the editor when clicked in the schema tree" do
    log_in
    visit new_query_path

    assert page.has_css?(".cm-editor", wait: 10)
    assert page.has_css?("[data-controller='schema-browser']", wait: 10)

    find("button", text: "Analytics").click
    find("button", text: "events").click

    within(".schema-browser") do
      find(".schema-browser__insertable", text: "user_id").click
    end

    assert page.has_css?(".cm-content", text: "user_id", wait: 10)
  end
end
