require "application_system_test_case"

class SchemaBrowserTest < ApplicationJsSystemTestCase
  setup do
    @user = create_user(role: "member", email: "member@example.com", password: "password")
    @connection = create_bigquery_connection

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
                { column_name: "user_id", data_type: "STRING",
                  is_nullable: true, ordinal_position: 1 },
                { column_name: "amount", data_type: "INT64",
                  is_nullable: false, ordinal_position: 2 }
              ]
            }
          ]
        }
      ]
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
  end

  def log_in
    visit new_session_path
    fill_in "メールアドレス", with: "member@example.com"
    fill_in "パスワード", with: "password"
    click_button "ログイン"
    assert page.has_content?("ログアウト", wait: 10)
  end

  test "renders the dataset/table/column tree (rack_test)" do
    log_in
    visit schema_browser_path

    assert page.has_content?("analytics")
    assert page.has_content?("events")
    assert page.has_content?("user_id")
    assert page.has_content?("amount")
    assert page.has_css?("[data-controller='schema-browser']")
    assert page.has_button?("スキーマを更新")
  end

  test "dispatches schema-browser:insert on column click" do
    log_in
    visit schema_browser_path

    received = page.evaluate_async_script(<<~JS)
      const done = arguments[0];
      document.addEventListener("schema-browser:insert", (e) => done(e.detail && e.detail.name), { once: true });
      const el = Array.from(document.querySelectorAll(".schema-browser__insertable"))
        .find((n) => n.textContent.trim() === "user_id");
      el.click();
    JS

    assert_equal "user_id", received
  end
end
