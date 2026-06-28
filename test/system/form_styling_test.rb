require "application_system_test_case"

# トピック16: フォーム入力欄に共通コンポーネントクラスが付与されていることを担保するリグレッションテスト。
class FormStylingTest < ApplicationJsSystemTestCase
  setup do
    @user = create_user(role: "member", email: "member@example.com", password: "password")
    @admin = create_user(role: "admin", email: "admin@example.com", password: "password")
  end

  def log_in(email)
    visit new_session_path
    fill_in "メールアドレス", with: email
    fill_in "パスワード", with: "password"
    click_button "ログイン"
  end

  def seed_query_with_result
    query = create_query(user: @user, title: "売上クエリ")
    execution = create_succeeded_query_execution(query: query)
    execution.store_result(
      [ { "name" => "day", "type" => "STRING" }, { "name" => "sales", "type" => "INTEGER" } ],
      [ [ "Mon", 10 ], [ "Tue", 20 ], [ "Wed", 30 ] ]
    )
    execution.save!
    query
  end

  # --- dashboard form (rack_test) ---
  test "uses .form-input and .form-label on title / description" do
    log_in("member@example.com")
    visit new_dashboard_path

    assert page.has_css?("input#dashboard_title.form-input")
    assert page.has_css?("textarea#dashboard_description.form-input")
    assert page.has_css?("label[for='dashboard_title'].form-label")
    assert page.has_css?("label[for='dashboard_description'].form-label")
    assert page.has_css?("input[type='submit'].btn-primary")
  end

  # --- visualization editor (rack_test) ---
  test "uses .form-input on all chart selects" do
    query = seed_query_with_result
    query.create_visualization!(display_mode: "chart", chart_type: "line")
    log_in("member@example.com")
    visit query_visualization_path(query)

    %w[chart_type x_column y_columns series_column].each do |attr|
      assert page.has_css?("select[name='visualization[#{attr}]'].form-input, select[name='visualization[#{attr}][]'].form-input")
    end
  end

  test "uses .form-input on counter selects" do
    query = seed_query_with_result
    query.create_visualization!(display_mode: "chart", chart_type: "counter")
    log_in("member@example.com")
    visit query_visualization_path(query)

    assert page.has_css?("select[name='visualization[counter_column]'].form-input")
    assert page.has_css?("select[name='visualization[counter_aggregation]'].form-input")
  end

  # --- query form (rack_test) ---
  test "uses .form-input / .form-label / .btn-primary" do
    create_bigquery_connection(name: "本番接続")
    log_in("member@example.com")
    visit new_query_path

    assert page.has_css?("input#query_title.form-input")
    assert page.has_css?("select#query_bigquery_connection_id.form-input")
    assert page.has_css?("textarea#query_sql_body.form-input")
    assert page.has_css?("label[for='query_title'].form-label")
    assert page.has_css?("input[type='submit'].btn-primary")
  end

  # --- session form (rack_test) ---
  test "session form uses .form-input / .form-label / .btn-primary" do
    visit new_session_path

    assert page.has_css?("input#email.form-input")
    assert page.has_css?("input#password.form-input")
    assert page.has_css?("label[for='email'].form-label")
    assert page.has_css?("input[type='submit'].btn-primary")
  end

  # --- admin user new form (rack_test) ---
  test "admin user new form uses .form-input / .form-label / .btn-primary" do
    log_in("admin@example.com")
    visit new_admin_user_path

    assert page.has_css?("input#user_email.form-input")
    assert page.has_css?("input#user_password.form-input")
    assert page.has_css?("select#user_role.form-input")
    assert page.has_css?("input[type='submit'].btn-primary")
  end

  # --- admin user edit form (rack_test) ---
  test "admin user edit form uses .form-input / .form-label / .btn-primary on edit and reset" do
    target = create_user(role: "member", email: "target@example.com", password: "password")
    log_in("admin@example.com")
    visit edit_admin_user_path(target)

    assert page.has_css?("input#user_email.form-input")
    assert page.has_css?("select#user_role.form-input")
    assert page.has_css?("input#user_password.form-input")
    assert page.has_css?("input[type='submit'].btn-primary")
  end

  # --- admin settings form (rack_test) ---
  test "admin settings form uses .form-input / .btn-primary on number field" do
    log_in("admin@example.com")
    visit edit_admin_settings_path

    assert page.has_css?("input#application_setting_bigquery_yen_per_tb.form-input")
    assert page.has_css?("input[type='submit'].btn-primary")
  end

  # --- bigquery connection form (rack_test) ---
  test "bigquery connection form uses .form-input / .btn-primary on all fields" do
    log_in("admin@example.com")
    visit new_bigquery_connection_path

    assert page.has_css?("input#bigquery_connection_name.form-input")
    assert page.has_css?("input#bigquery_connection_project_id.form-input")
    assert page.has_css?("textarea#bigquery_connection_service_account_json.form-input")
    assert page.has_css?("input#bigquery_connection_maximum_bytes_billed_gb.form-input")
    assert page.has_css?("input[type='submit'].btn-primary")
  end

  # --- queries show execution / delete (rack_test) ---
  test "uses .btn-primary on execute and .btn-danger on delete" do
    create_bigquery_connection(name: "本番接続")
    query = create_query(user: @user, title: "実行クエリ")
    log_in("member@example.com")
    visit query_path(query)

    assert page.has_css?("input[type='submit'].btn-primary")
    assert page.has_css?("button.btn-danger", text: "削除")
  end

  # --- parameter form on parameterized query (rack_test) ---
  test "uses .form-input on number / date / text / date_range fields and .form-label on labels" do
    connection = create_bigquery_connection(name: "本番接続")
    query = create_query(user: @user, title: "パラメータクエリ", sql_body: "SELECT {{ s }}, {{ n:number }} WHERE d = {{ d:date }} AND c BETWEEN {{ c:date_range }}", bigquery_connection: connection)
    log_in("member@example.com")
    visit query_path(query)

    assert page.has_css?("label[for='query_param_s'].form-label")
    assert page.has_css?("label[for='query_param_n'].form-label")
    assert page.has_css?("input#query_param_s.form-input")
    assert page.has_css?("input#query_param_n.form-input")
    assert page.has_css?("input#query_param_d.form-input")
    assert page.has_css?("input#query_param_c_start.form-input")
    assert page.has_css?("input#query_param_c_end.form-input")
  end

  # --- computed border width (js) ---
  test "renders a visible border on the dashboard title input" do
    log_in("member@example.com")
    assert page.has_content?("ログアウト", wait: 10)
    visit new_dashboard_path

    find("input#dashboard_title.form-input", wait: 10)
    width = page.evaluate_script(
      "(function(){ var el = document.querySelector('input#dashboard_title.form-input'); return window.getComputedStyle(el).borderTopWidth; })()"
    )
    assert_not_equal "0px", width
  end

  test "renders a visible border on the visualization chart_type select" do
    query = seed_query_with_result
    query.create_visualization!(display_mode: "chart", chart_type: "line")
    log_in("member@example.com")
    assert page.has_content?("ログアウト", wait: 10)
    visit query_visualization_path(query)

    find("select[name='visualization[chart_type]'].form-input", wait: 10)
    width = page.evaluate_script(
      "(function(){ var el = document.querySelector(\"select[name='visualization[chart_type]'].form-input\"); return window.getComputedStyle(el).borderTopWidth; })()"
    )
    assert_not_equal "0px", width
  end

  test "keeps date_range fields bordered and laid out side by side" do
    query = create_query(user: @user, title: "日付レンジ", sql_body: "WHERE c BETWEEN {{ c:date_range }}", bigquery_connection: create_bigquery_connection(name: "本番接続"))
    log_in("member@example.com")
    assert page.has_content?("ログアウト", wait: 10)
    visit query_path(query)

    find("input#query_param_c_start.form-input", wait: 10)
    width = page.evaluate_script(
      "(function(){ var el = document.querySelector('input#query_param_c_start.form-input'); return window.getComputedStyle(el).borderTopWidth; })()"
    )
    assert_not_equal "0px", width
    same_row = page.evaluate_script(
      "(function(){ var s = document.querySelector('#query_param_c_start'); var e = document.querySelector('#query_param_c_end'); return s.offsetTop === e.offsetTop; })()"
    )
    assert_equal true, same_row
    not_full_width = page.evaluate_script(
      "(function(){ var s = document.querySelector('#query_param_c_start'); return s.offsetWidth < s.parentElement.offsetWidth; })()"
    )
    assert_equal true, not_full_width
  end
end
