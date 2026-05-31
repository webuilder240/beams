require "rails_helper"

# トピック16: フォーム入力欄に共通コンポーネントクラス（.form-input / .form-label /
# .btn-*）が付与されていることを担保するリグレッションテスト。
# rack_test は CSS を評価しないため、ここではマークアップ上のスタイルフックの存在を
# 検証する「構造テスト」。実際の枠線描画（getComputedStyle）は js: true の example で検証する。
RSpec.describe "Form styling consistency", type: :system do
  let!(:user) { create(:user, :member, email: "member@example.com", password: "password") }
  let!(:admin) { create(:user, :admin, email: "admin@example.com", password: "password") }

  def log_in(email)
    visit new_session_path
    fill_in "メールアドレス", with: email
    fill_in "パスワード", with: "password"
    click_button "ログイン"
  end

  def seed_query_with_result
    query = create(:query, user: user, title: "売上クエリ")
    execution = create(:query_execution, :succeeded, query: query)
    execution.store_result(
      [ { "name" => "day", "type" => "STRING" }, { "name" => "sales", "type" => "INTEGER" } ],
      [ [ "Mon", 10 ], [ "Tue", 20 ], [ "Wed", 30 ] ]
    )
    execution.save!
    query
  end

  describe "dashboard form (rack_test)" do
    it "uses .form-input and .form-label on title / description" do
      log_in("member@example.com")
      visit new_dashboard_path

      expect(page).to have_css("input#dashboard_title.form-input")
      expect(page).to have_css("textarea#dashboard_description.form-input")
      expect(page).to have_css("label[for='dashboard_title'].form-label")
      expect(page).to have_css("label[for='dashboard_description'].form-label")
      expect(page).to have_css("input[type='submit'].btn-primary")
    end
  end

  describe "visualization editor (rack_test)" do
    it "uses .form-input on all chart selects" do
      query = seed_query_with_result
      query.create_visualization!(display_mode: "chart", chart_type: "line")
      log_in("member@example.com")
      visit query_visualization_path(query)

      %w[chart_type x_column y_columns series_column].each do |attr|
        expect(page).to have_css("select[name='visualization[#{attr}]'].form-input, select[name='visualization[#{attr}][]'].form-input")
      end
    end

    it "uses .form-input on counter selects" do
      query = seed_query_with_result
      query.create_visualization!(display_mode: "chart", chart_type: "counter")
      log_in("member@example.com")
      visit query_visualization_path(query)

      expect(page).to have_css("select[name='visualization[counter_column]'].form-input")
      expect(page).to have_css("select[name='visualization[counter_aggregation]'].form-input")
    end
  end

  describe "query form (rack_test)" do
    let!(:connection) { create(:bigquery_connection, name: "本番接続") }

    it "uses .form-input / .form-label / .btn-primary" do
      log_in("member@example.com")
      visit new_query_path

      expect(page).to have_css("input#query_title.form-input")
      expect(page).to have_css("select#query_bigquery_connection_id.form-input")
      expect(page).to have_css("textarea#query_sql_body.form-input")
      expect(page).to have_css("label[for='query_title'].form-label")
      expect(page).to have_css("input[type='submit'].btn-primary")
    end
  end

  describe "session form (rack_test)" do
    it "uses .form-input / .form-label / .btn-primary" do
      visit new_session_path

      expect(page).to have_css("input#email.form-input")
      expect(page).to have_css("input#password.form-input")
      expect(page).to have_css("label[for='email'].form-label")
      expect(page).to have_css("input[type='submit'].btn-primary")
    end
  end

  describe "admin user new form (rack_test)" do
    it "uses .form-input / .form-label / .btn-primary" do
      log_in("admin@example.com")
      visit new_admin_user_path

      expect(page).to have_css("input#user_email.form-input")
      expect(page).to have_css("input#user_password.form-input")
      expect(page).to have_css("select#user_role.form-input")
      expect(page).to have_css("input[type='submit'].btn-primary")
    end
  end

  describe "admin user edit form (rack_test)" do
    it "uses .form-input / .form-label / .btn-primary on edit and reset" do
      target = create(:user, :member, email: "target@example.com", password: "password")
      log_in("admin@example.com")
      visit edit_admin_user_path(target)

      expect(page).to have_css("input#user_email.form-input")
      expect(page).to have_css("select#user_role.form-input")
      expect(page).to have_css("input#user_password.form-input")
      expect(page).to have_css("input[type='submit'].btn-primary")
    end
  end

  describe "admin settings form (rack_test)" do
    it "uses .form-input / .btn-primary on number field" do
      log_in("admin@example.com")
      visit edit_admin_settings_path

      expect(page).to have_css("input#application_setting_bigquery_yen_per_tb.form-input")
      expect(page).to have_css("input[type='submit'].btn-primary")
    end
  end

  describe "bigquery connection form (rack_test)" do
    it "uses .form-input / .btn-primary on all fields" do
      log_in("admin@example.com")
      visit new_bigquery_connection_path

      expect(page).to have_css("input#bigquery_connection_name.form-input")
      expect(page).to have_css("input#bigquery_connection_project_id.form-input")
      expect(page).to have_css("textarea#bigquery_connection_service_account_json.form-input")
      expect(page).to have_css("input#bigquery_connection_maximum_bytes_billed_gb.form-input")
      expect(page).to have_css("input[type='submit'].btn-primary")
    end
  end

  describe "queries show execution / delete (rack_test)" do
    let!(:connection) { create(:bigquery_connection, name: "本番接続") }

    it "uses .btn-primary on execute and .btn-danger on delete" do
      query = create(:query, user: user, title: "実行クエリ")
      log_in("member@example.com")
      visit query_path(query)

      expect(page).to have_css("input[type='submit'].btn-primary")
      expect(page).to have_css("button.btn-danger", text: "削除")
    end
  end

  describe "parameter form on parameterized query (rack_test)" do
    let!(:connection) { create(:bigquery_connection, name: "本番接続") }

    it "uses .form-input on number / date / text / date_range fields and .form-label on labels" do
      query = create(:query, user: user, title: "パラメータクエリ",
                     sql_body: "SELECT {{ s }}, {{ n:number }} WHERE d = {{ d:date }} AND c BETWEEN {{ c:date_range }}",
                     bigquery_connection: connection)
      log_in("member@example.com")
      visit query_path(query)

      # ラベル
      expect(page).to have_css("label[for='query_param_s'].form-label")
      expect(page).to have_css("label[for='query_param_n'].form-label")
      # 全幅入力（string / number / date）
      expect(page).to have_css("input#query_param_s.form-input")
      expect(page).to have_css("input#query_param_n.form-input")
      expect(page).to have_css("input#query_param_d.form-input")
      # date_range の 2 フィールドも .form-input を持つ（横並び維持のため w-auto を併用）
      expect(page).to have_css("input#query_param_c_start.form-input")
      expect(page).to have_css("input#query_param_c_end.form-input")
    end
  end

  # 厳密リグレッション（CSS リグレッション）: 実際に枠線幅が 0px でないことを Playwright で検証。
  # 修正前は border-width:0（Preflight）で失敗、修正後は border-width > 0 で green。
  describe "computed border width (js)", :js do
    it "renders a visible border on the dashboard title input" do
      log_in("member@example.com")
      expect(page).to have_content("ログアウト", wait: 10)
      visit new_dashboard_path

      input = find("input#dashboard_title.form-input", wait: 10)
      width = page.evaluate_script(
        "(function(){ var el = document.querySelector('input#dashboard_title.form-input'); return window.getComputedStyle(el).borderTopWidth; })()"
      )
      expect(width).not_to eq("0px")
    end

    it "renders a visible border on the visualization chart_type select" do
      query = seed_query_with_result
      query.create_visualization!(display_mode: "chart", chart_type: "line")
      log_in("member@example.com")
      expect(page).to have_content("ログアウト", wait: 10)
      visit query_visualization_path(query)

      find("select[name='visualization[chart_type]'].form-input", wait: 10)
      width = page.evaluate_script(
        "(function(){ var el = document.querySelector(\"select[name='visualization[chart_type]'].form-input\"); return window.getComputedStyle(el).borderTopWidth; })()"
      )
      expect(width).not_to eq("0px")
    end

    it "keeps date_range fields bordered and laid out side by side" do
      query = create(:query, user: user, title: "日付レンジ",
                     sql_body: "WHERE c BETWEEN {{ c:date_range }}",
                     bigquery_connection: create(:bigquery_connection, name: "本番接続"))
      log_in("member@example.com")
      expect(page).to have_content("ログアウト", wait: 10)
      visit query_path(query)

      find("input#query_param_c_start.form-input", wait: 10)
      # 枠線が描画されている
      width = page.evaluate_script(
        "(function(){ var el = document.querySelector('input#query_param_c_start.form-input'); return window.getComputedStyle(el).borderTopWidth; })()"
      )
      expect(width).not_to eq("0px")
      # 開始・終了が横並び（同じ行＝offsetTop が一致）かつ全幅化していない（start が親より狭い）
      same_row = page.evaluate_script(
        "(function(){ var s = document.querySelector('#query_param_c_start'); var e = document.querySelector('#query_param_c_end'); return s.offsetTop === e.offsetTop; })()"
      )
      expect(same_row).to eq(true)
      not_full_width = page.evaluate_script(
        "(function(){ var s = document.querySelector('#query_param_c_start'); return s.offsetWidth < s.parentElement.offsetWidth; })()"
      )
      expect(not_full_width).to eq(true)
    end
  end
end
