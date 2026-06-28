require "application_system_test_case"
require "google/cloud/bigquery"
require "ostruct"

# rack_test（JSなし）。非同期部分はジョブをインライン実行して結果反映まで確認する。
class QueryExecutionTest < ApplicationSystemTestCase
  setup do
    @user = create_user(role: "member", email: "member@example.com", password: "password")
    @connection = create_bigquery_connection(name: "本番接続", maximum_bytes_billed: nil)
    @original_adapter = ActiveJob::Base.queue_adapter
    ActiveJob::Base.queue_adapter = :inline
    @bigquery_original = Bigquery::Connection.instance_method(:bigquery)
  end

  teardown do
    ActiveJob::Base.queue_adapter = @original_adapter
    Bigquery::Connection.define_method(:bigquery, @bigquery_original) if @bigquery_original
  end

  def log_in
    visit new_session_path
    fill_in "メールアドレス", with: "member@example.com"
    fill_in "パスワード", with: "password"
    click_button "ログイン"
  end

  # BigQuery を行データ付きでスタブする。
  def stub_bigquery(rows:, fields:)
    field_objs = fields.map { |f| OpenStruct.new(name: f[:name], type: f[:type]) }
    data = Object.new
    data.define_singleton_method(:fields) { field_objs }
    data.define_singleton_method(:each) { |&blk| rows.each(&blk) }
    data.define_singleton_method(:map) { |&blk| rows.map(&blk) }

    bq_job = Object.new
    bq_job.define_singleton_method(:wait_until_done!) { nil }
    bq_job.define_singleton_method(:failed?) { false }
    bq_job.define_singleton_method(:data) { data }

    client = Object.new
    client.define_singleton_method(:query_job) { |*_a, **_k| bq_job }

    Bigquery::Connection.define_method(:bigquery) { client }
  end

  def stub_bigquery_error(message)
    client = Object.new
    client.define_singleton_method(:query_job) do |*_a, **_k|
      raise Google::Cloud::Error.new(message)
    end
    Bigquery::Connection.define_method(:bigquery) { client }
  end

  test "runs a query and shows the result after the job completes" do
    stub_bigquery(rows: [ { n: 1 } ], fields: [ { name: "n", type: "INTEGER" } ])
    query = create_query(user: @user, title: "実行クエリ", sql_body: "SELECT 1 AS n", bigquery_connection: @connection)
    log_in
    visit query_path(query)

    assert page.has_button?("実行")
    click_button "実行"

    execution = query.query_executions.order(:created_at).last
    assert execution.succeeded?

    visit query_path(query)
    assert page.has_content?("n")
    assert page.has_content?("1")
    assert page.has_link?("CSVダウンロード")
  end

  test "shows an error when the query fails" do
    stub_bigquery_error("invalid query: boom")

    query = create_query(user: @user, title: "失敗クエリ", sql_body: "SELECT bad", bigquery_connection: @connection)
    log_in
    visit query_path(query)
    click_button "実行"

    visit query_path(query)
    assert page.has_content?("エラー")
    assert page.has_content?("invalid query: boom")
  end

  test "lists execution history newest-first and re-displays a past result (トピック17)" do
    stub_bigquery(rows: [ { n: 1 } ], fields: [ { name: "n", type: "INTEGER" } ])
    query = create_query(user: @user, title: "履歴クエリ", sql_body: "SELECT 1 AS n", bigquery_connection: @connection)
    log_in
    visit query_path(query)

    click_button "実行"
    visit query_path(query)
    click_button "実行"

    visit query_path(query)
    assert page.has_content?("実行履歴")
    assert page.has_css?("#query_history_rows tr", minimum: 2)
    assert page.has_content?("succeeded")

    first(:link, "結果を表示").click
    assert page.has_content?("n")
    assert page.has_content?("1")
  end

  test "keeps a failed execution with its error message in the history (トピック17)" do
    stub_bigquery_error("invalid query: histfail")

    query = create_query(user: @user, title: "履歴失敗クエリ", sql_body: "SELECT bad", bigquery_connection: @connection)
    log_in
    visit query_path(query)
    click_button "実行"

    visit query_path(query)
    assert page.has_content?("実行履歴")
    within("#query_history_rows") do
      assert page.has_content?("failed")
      assert page.has_content?("invalid query: histfail")
    end
  end

  test "shows the truncation banner when results exceed the row limit" do
    rows = Array.new(10_001) { |i| { n: i } }
    stub_bigquery(rows: rows, fields: [ { name: "n", type: "INTEGER" } ])
    query = create_query(user: @user, title: "大量クエリ", sql_body: "SELECT n", bigquery_connection: @connection)
    log_in
    visit query_path(query)
    click_button "実行"

    visit query_path(query)
    assert page.has_content?("全件はCSVダウンロード")
  end
end
