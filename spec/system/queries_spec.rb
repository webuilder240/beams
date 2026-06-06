require "rails_helper"

RSpec.describe "Query editor", type: :system do
  let!(:user) { create(:user, :member, email: "member@example.com", password: "password") }
  let!(:connection) { create(:bigquery_connection, name: "本番接続") }

  def log_in
    visit new_session_path
    fill_in "メールアドレス", with: "member@example.com"
    fill_in "パスワード", with: "password"
    click_button "ログイン"
  end

  it "lets a user create, view, and delete a query (rack_test)" do
    log_in
    visit queries_path
    click_link "新規クエリ"

    fill_in "タイトル", with: "売上集計クエリ"
    select "本番接続", from: "実行先 BigQuery 接続"
    fill_in "SQL", with: "SELECT COUNT(*) FROM sales"
    click_button "保存"

    # 保存後は show へリダイレクト
    expect(page).to have_content("売上集計クエリ")
    expect(page).to have_content("SELECT COUNT(*) FROM sales")
    expect(page).to have_content("本番接続")

    # 一覧に出る
    visit queries_path
    expect(page).to have_content("売上集計クエリ")

    # 削除 → index へ
    within("tr", text: "売上集計クエリ") { click_button "削除" }
    expect(page).to have_current_path(queries_path)
    expect(page).not_to have_content("売上集計クエリ")
  end

  it "edits an existing query and shows the saved SQL in the form (rack_test)" do
    query = create(:query, user: user, title: "編集対象", sql_body: "SELECT 42", bigquery_connection: connection)
    log_in
    visit edit_query_path(query)

    # 隠し textarea（フォールバック）に既存 SQL が入っている
    expect(page).to have_field("SQL", with: "SELECT 42")

    fill_in "タイトル", with: "編集済み"
    click_button "更新"

    expect(page).to have_content("編集済み")
  end

  it "searches queries by title (rack_test)" do
    create(:query, user: user, title: "売上レポート", bigquery_connection: connection)
    create(:query, user: user, title: "在庫一覧", bigquery_connection: connection)
    log_in
    visit queries_path

    fill_in "タイトル/SQL本文で検索", with: "売上"
    click_button "検索"

    expect(page).to have_content("売上レポート")
    expect(page).not_to have_content("在庫一覧")
  end

  it "searches queries by SQL body (rack_test, トピック21)" do
    create(:query, user: user, title: "Untitled",
                   sql_body: "SELECT user_id FROM events", bigquery_connection: connection)
    create(:query, user: user, title: "別件",
                   sql_body: "SELECT name FROM products", bigquery_connection: connection)
    log_in
    visit queries_path

    fill_in "タイトル/SQL本文で検索", with: "user_id"
    click_button "検索"

    expect(page).to have_content("Untitled")
    expect(page).not_to have_content("別件")
  end

  it "lists all users' queries with owner names (org full-open §4.9, rack_test)" do
    other_user = create(:user, :member, email: "other@example.com", password: "password")
    create(:query, user: user, title: "自分のクエリ", bigquery_connection: connection)
    create(:query, user: other_user, title: "他人のクエリ", bigquery_connection: connection)

    log_in
    visit queries_path

    # 全ユーザーのクエリが見える（§4.9）
    expect(page).to have_content("自分のクエリ")
    expect(page).to have_content("他人のクエリ")
    # 所有者名（email）が一覧に表示される
    expect(page).to have_content("member@example.com")
    expect(page).to have_content("other@example.com")
  end

  it "guides to connection registration when no connection exists (rack_test)" do
    connection.destroy
    log_in
    visit new_query_path

    expect(page).to have_content("BigQuery 接続がありません")
    expect(page).to have_link("BigQuery 接続を登録")
  end

  it "renders the query-editor Stimulus mount on the new form (rack_test)" do
    log_in
    visit new_query_path

    expect(page).to have_css("[data-controller='query-editor']")
    expect(page).to have_css("[data-query-editor-target='mount']")
  end
end
