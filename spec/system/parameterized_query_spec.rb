require "rails_helper"

RSpec.describe "Parameterized query", type: :system do
  let!(:user) { create(:user, :member, email: "member@example.com", password: "password") }
  let!(:connection) { create(:bigquery_connection, name: "本番接続") }

  def log_in
    visit new_session_path
    fill_in "メールアドレス", with: "member@example.com"
    fill_in "パスワード", with: "password"
    click_button "ログイン"
  end

  it "shows the parameter form on a parameterized query and accepts input (rack_test)" do
    query = create(:query, user: user, title: "パラメータクエリ",
                   sql_body: "SELECT * FROM t WHERE id = {{ user_id:number }}", bigquery_connection: connection)
    log_in
    visit query_path(query)

    expect(page).to have_content("パラメータ")
    expect(page).to have_field("user_id")

    fill_in "user_id", with: "42"
    click_button "パラメータを適用"

    expect(page).to have_content("パラメータを受け付けました")
  end

  it "rejects submission when a required parameter is left blank (server-side, rack_test)" do
    query = create(:query, user: user, title: "必須パラメータ",
                   sql_body: "SELECT {{ a }}, {{ b }}", bigquery_connection: connection)
    log_in
    visit query_path(query)

    # rack_test は HTML5 required を強制しないため、b を空のまま送信でき、
    # サーバ側の必須チェック（全パラメータ必須）が働くことを確認する。
    fill_in "a", with: "1"
    click_button "パラメータを適用"

    expect(page).to have_content("未入力のパラメータがあります")
  end

  it "does not show a parameter form for a query without parameters (rack_test)" do
    query = create(:query, user: user, title: "ノーパラメータ",
                   sql_body: "SELECT 1", bigquery_connection: connection)
    log_in
    visit query_path(query)

    expect(page).not_to have_content("パラメータを適用")
  end

  it "renders date and date_range fields for those parameter types (rack_test)" do
    query = create(:query, user: user, title: "日付パラメータ",
                   sql_body: "WHERE d = {{ d:date }} AND c BETWEEN {{ c:date_range }}", bigquery_connection: connection)
    log_in
    visit query_path(query)

    expect(page).to have_css("input#query_param_d[type='date']")
    expect(page).to have_css("input#query_param_c_start[type='date']")
    expect(page).to have_css("input#query_param_c_end[type='date']")
  end

  it "renders the parameter-form preview container on the edit form (rack_test)" do
    query = create(:query, user: user, sql_body: "SELECT 1", bigquery_connection: connection)
    log_in
    visit edit_query_path(query)

    expect(page).to have_css("[data-controller='parameter-form']")
    expect(page).to have_css("[data-parameter-form-target='fields']")
  end
end
