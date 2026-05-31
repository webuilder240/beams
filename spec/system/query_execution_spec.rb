require "rails_helper"
require "google/cloud/bigquery"

# rack_test（JSなし）。非同期部分はジョブをインライン実行して結果反映まで確認する。
# Turbo Streams のライブ差し込み（WebSocket）は JS 依存のため、ここでは
# インライン実行後に show を再訪して結果が表示されることで一連フローを検証する。
RSpec.describe "Query execution", type: :system do
  let!(:user) { create(:user, :member, email: "member@example.com", password: "password") }
  let(:connection) { create(:bigquery_connection, name: "本番接続", maximum_bytes_billed: nil) }

  around do |example|
    original = ActiveJob::Base.queue_adapter
    ActiveJob::Base.queue_adapter = :inline
    example.run
    ActiveJob::Base.queue_adapter = original
  end

  def log_in
    visit new_session_path
    fill_in "メールアドレス", with: "member@example.com"
    fill_in "パスワード", with: "password"
    click_button "ログイン"
  end

  # BigQuery を行データ付きでスタブする。
  def stub_bigquery(rows:, fields:)
    field_doubles = fields.map do |f|
      instance_double(Google::Cloud::Bigquery::Schema::Field, name: f[:name], type: f[:type])
    end
    data = instance_double(Google::Cloud::Bigquery::Data, fields: field_doubles)
    allow(data).to receive(:each) { |&blk| rows.each(&blk) }
    allow(data).to receive(:map) { |&blk| rows.map(&blk) }
    bq_job = instance_double(Google::Cloud::Bigquery::QueryJob,
                             wait_until_done!: nil, failed?: false, data: data)
    client = instance_double(Google::Cloud::Bigquery::Project, query_job: bq_job)
    allow_any_instance_of(Bigquery::Connection).to receive(:bigquery).and_return(client)
  end

  it "runs a query and shows the result after the job completes" do
    stub_bigquery(rows: [ { n: 1 } ], fields: [ { name: "n", type: "INTEGER" } ])
    query = create(:query, user: user, title: "実行クエリ",
                   sql_body: "SELECT 1 AS n", bigquery_connection: connection)
    log_in
    visit query_path(query)

    expect(page).to have_button("実行")
    click_button "実行"

    # インライン実行で succeeded まで進む。show を再訪して結果テーブルを確認する。
    execution = query.query_executions.order(:created_at).last
    expect(execution).to be_succeeded

    visit query_path(query)
    expect(page).to have_content("n")
    expect(page).to have_content("1")
    expect(page).to have_link("CSVダウンロード")
  end

  it "shows an error when the query fails" do
    client = instance_double(Google::Cloud::Bigquery::Project)
    allow(client).to receive(:query_job).and_raise(Google::Cloud::Error.new("invalid query: boom"))
    allow_any_instance_of(Bigquery::Connection).to receive(:bigquery).and_return(client)

    query = create(:query, user: user, title: "失敗クエリ",
                   sql_body: "SELECT bad", bigquery_connection: connection)
    log_in
    visit query_path(query)
    click_button "実行"

    visit query_path(query)
    expect(page).to have_content("エラー")
    expect(page).to have_content("invalid query: boom")
  end

  it "lists execution history newest-first and re-displays a past result (トピック17)" do
    stub_bigquery(rows: [ { n: 1 } ], fields: [ { name: "n", type: "INTEGER" } ])
    query = create(:query, user: user, title: "履歴クエリ",
                   sql_body: "SELECT 1 AS n", bigquery_connection: connection)
    log_in
    visit query_path(query)

    # 2 回実行して履歴を 2 件にする。
    click_button "実行"
    visit query_path(query)
    click_button "実行"

    visit query_path(query)
    expect(page).to have_content("実行履歴")
    # 成功実行は履歴に並び、状態バッジ・行数が見える。
    expect(page).to have_css("#query_history_rows tr", minimum: 2)
    expect(page).to have_content("succeeded")

    # 過去実行の「結果を表示」で結果テーブルが再描画される（rack_test: 遷移）。
    first(:link, "結果を表示").click
    expect(page).to have_content("n")
    expect(page).to have_content("1")
  end

  it "keeps a failed execution with its error message in the history (トピック17)" do
    client = instance_double(Google::Cloud::Bigquery::Project)
    allow(client).to receive(:query_job).and_raise(Google::Cloud::Error.new("invalid query: histfail"))
    allow_any_instance_of(Bigquery::Connection).to receive(:bigquery).and_return(client)

    query = create(:query, user: user, title: "履歴失敗クエリ",
                   sql_body: "SELECT bad", bigquery_connection: connection)
    log_in
    visit query_path(query)
    click_button "実行"

    visit query_path(query)
    expect(page).to have_content("実行履歴")
    within("#query_history_rows") do
      expect(page).to have_content("failed")
      expect(page).to have_content("invalid query: histfail")
    end
  end

  it "shows the truncation banner when results exceed the row limit" do
    rows = Array.new(10_001) { |i| { n: i } }
    stub_bigquery(rows: rows, fields: [ { name: "n", type: "INTEGER" } ])
    query = create(:query, user: user, title: "大量クエリ",
                   sql_body: "SELECT n", bigquery_connection: connection)
    log_in
    visit query_path(query)
    click_button "実行"

    visit query_path(query)
    expect(page).to have_content("全件はCSVダウンロード")
  end
end
