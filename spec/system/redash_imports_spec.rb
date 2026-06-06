require "rails_helper"

# Redash クエリ取り込みの一連の System Spec（rack_test）。
# - admin が `/admin/redash_sources` で Redash 接続を作成
# - member が `/redash_imports/new` から RedashSource を選び、クエリ一覧を表示し、
#   複数選択して BigQuery 接続を指定して取り込む
# - 結果画面で「成功 N 件 / 失敗 M 件 / 警告つき」が表示される
RSpec.describe "Redash imports", type: :system do
  let!(:admin)  { create(:user, :admin,  email: "admin@example.com",  password: "password") }
  let!(:member) { create(:user, :member, email: "member@example.com", password: "password") }
  let!(:bq_connection) { create(:bigquery_connection, name: "本番BigQuery") }

  before do
    # SSRF ガードを通す（テストでは Resolv をスタブして公開 IP に解決させる）
    allow(Resolv).to receive(:getaddresses).and_return([ "203.0.113.10" ])
  end

  def log_in(email)
    visit new_session_path
    fill_in "メールアドレス", with: email
    fill_in "パスワード", with: "password"
    click_button "ログイン"
  end

  it "admin が Redash 接続を作成し、member が複数クエリを取り込んで結果を確認できる" do
    # ---- admin: Redash 接続を作成 ----
    log_in("admin@example.com")
    visit admin_redash_sources_path
    click_link "新規接続"

    fill_in "接続名", with: "社内Redash"
    fill_in "Redash URL", with: "https://redash.example.com"
    fill_in "API キー", with: "user_api_key_xyz"
    click_button "作成"

    expect(page).to have_content("Redash 接続を作成しました")
    expect(page).to have_content("社内Redash")

    # ---- API のスタブ（list + 詳細 2 件） ----
    stub_request(:get, /redash\.example\.com\/api\/queries\?/)
      .to_return(status: 200, body: {
        "count" => 2, "page" => 1, "page_size" => 50,
        "results" => [
          { "id" => 100, "name" => "DAU" },
          { "id" => 101, "name" => "Datetime sample" }
        ]
      }.to_json, headers: { "Content-Type" => "application/json" })

    stub_request(:get, "https://redash.example.com/api/queries/100")
      .to_return(status: 200, body: {
        "id" => 100, "name" => "DAU",
        "query" => "SELECT count(*) FROM users WHERE created_at >= {{ start_date }}",
        "options" => { "parameters" => [ { "name" => "start_date", "type" => "date" } ] }
      }.to_json)

    stub_request(:get, "https://redash.example.com/api/queries/101")
      .to_return(status: 200, body: {
        "id" => 101, "name" => "Datetime sample",
        "query" => "SELECT 1",
        "options" => { "parameters" => [ { "name" => "ts", "type" => "datetime-local" } ] }
      }.to_json)

    # ---- member: クエリ一覧から「Redashから取り込み」 ----
    click_button "ログアウト" if page.has_button?("ログアウト")
    log_in("member@example.com")

    visit queries_path
    click_link "Redashから取り込み"

    select "社内Redash（https://redash.example.com）", from: "Redash 接続"
    click_button "次へ：クエリ一覧を取得"

    expect(page).to have_content("DAU")
    expect(page).to have_content("Datetime sample")

    # 2 件のクエリと BigQuery 接続を選択して取り込み
    check "query_id_100"
    check "query_id_101"
    select "本番BigQuery", from: "取り込み先 BigQuery 接続"
    click_button "取り込み実行"

    expect(page).to have_content("Redash 取り込み結果")
    expect(page).to have_content("成功")
    expect(page).to have_content("DAU")
    expect(page).to have_content("Datetime sample")
    # 警告（datetime-local → string）が表示されている
    expect(page).to have_content(/警告/)

    # Beams 側に Query が 2 件作成されている
    dau = Query.find_by(title: "DAU")
    expect(dau).not_to be_nil
    expect(dau.user_id).to eq(member.id)
    expect(dau.bigquery_connection_id).to eq(bq_connection.id)
    expect(dau.query_parameters.pluck(:name, :param_type)).to eq([ [ "start_date", "date" ] ])
  end

  it "Redash API が 401 を返した場合は新規取り込み画面にエラーが表示される" do
    log_in("admin@example.com")
    visit new_admin_redash_source_path
    fill_in "接続名", with: "壊れたRedash"
    fill_in "Redash URL", with: "https://redash.example.com"
    fill_in "API キー", with: "bad_key"
    click_button "作成"

    click_button "ログアウト" if page.has_button?("ログアウト")
    log_in("member@example.com")

    stub_request(:get, /redash\.example\.com\/api\/queries/).to_return(status: 401)

    visit queries_path
    click_link "Redashから取り込み"
    select "壊れたRedash（https://redash.example.com）", from: "Redash 接続"
    click_button "次へ：クエリ一覧を取得"

    expect(page).to have_content("Redash の API キーが無効です")
  end
end
