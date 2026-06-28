# frozen_string_literal: true

require "test_helper"
require "google/cloud/bigquery"

class QueryExecutionJobTest < ActiveJob::TestCase
  # BigQuery クライアントと query_job をスタブする（実 API は呼ばない）。
  # data は Google::Cloud::Bigquery::Data 風: each で Hash 行を返し、
  # #fields で列スキーマ（name/type）を返す。
  #
  # 戻り値の Hash には :client / :job / :data の double と、
  # query_job 呼び出し時の引数を記録する :query_job_calls 配列を含む。
  def stub_bigquery(rows:, fields:)
    field_doubles = fields.map do |f|
      Struct.new(:name, :type).new(f[:name], f[:type])
    end

    data = Object.new
    data.define_singleton_method(:fields) { field_doubles }
    data.define_singleton_method(:each) { |&blk| rows.each(&blk); self }
    data.define_singleton_method(:map) { |&blk| rows.map(&blk) }

    bq_job = Object.new
    bq_job.define_singleton_method(:wait_until_done!) { nil }
    bq_job.define_singleton_method(:failed?) { false }
    bq_job.define_singleton_method(:data) { data }

    query_job_calls = []
    client = Object.new
    client.define_singleton_method(:query_job) do |sql, **opts|
      query_job_calls << { sql: sql, opts: opts }
      bq_job
    end

    install_bigquery_client(client)
    { client: client, job: bq_job, data: data, query_job_calls: query_job_calls }
  end

  # Bigquery::Connection#bigquery をスタブ用クライアントに差し替えるユーティリティ。
  # teardown で元のメソッドに戻す。
  def install_bigquery_client(client)
    @__original_bigquery_method = Bigquery::Connection.instance_method(:bigquery) rescue nil
    Bigquery::Connection.define_method(:bigquery) { client }
  end

  def uninstall_bigquery_client
    if @__original_bigquery_method
      Bigquery::Connection.define_method(:bigquery, @__original_bigquery_method)
      @__original_bigquery_method = nil
    elsif Bigquery::Connection.method_defined?(:bigquery)
      Bigquery::Connection.remove_method(:bigquery) rescue nil
    end
  end

  # QueryExecutionJob.broadcast_result をスタブし、呼び出しを記録する。
  def stub_broadcast
    @__broadcast_calls = []
    @__original_broadcast = QueryExecutionJob.method(:broadcast_result)
    calls = @__broadcast_calls
    QueryExecutionJob.define_singleton_method(:broadcast_result) do |execution|
      calls << execution
      nil
    end
  end

  def unstub_broadcast
    if @__original_broadcast
      QueryExecutionJob.singleton_class.remove_method(:broadcast_result)
      QueryExecutionJob.define_singleton_method(:broadcast_result, @__original_broadcast)
    end
  end

  setup do
    FileUtils.rm_rf(Pathname.new(ENV.fetch("BEAMS_CSV_PATH") { Rails.root.join("storage/csv").to_s }))
    stub_broadcast
  end

  teardown do
    unstub_broadcast
    uninstall_bigquery_client
  end

  # --- success path ---

  test "transitions to succeeded and stores the compressed result" do
    connection = create_bigquery_connection(maximum_bytes_billed: nil)
    query = create_query(bigquery_connection: connection, sql_body: "SELECT 1 AS n")
    execution = create_query_execution(query: query)

    stub_bigquery(
      rows: [ { n: 1 }, { n: 2 } ],
      fields: [ { name: "n", type: "INTEGER" } ]
    )

    QueryExecutionJob.perform_now(execution)
    execution.reload

    assert_predicate execution, :succeeded?
    assert_predicate execution.started_at, :present?
    assert_predicate execution.finished_at, :present?
    assert_equal 2, execution.result_row_count
    assert_equal false, execution.result_truncated
    result = execution.result
    assert_equal [ { "name" => "n", "type" => "INTEGER" } ], result[:schema]
    assert_equal [ [ 1 ], [ 2 ] ], result[:rows]
  end

  test "writes a gzip CSV file for the execution" do
    connection = create_bigquery_connection(maximum_bytes_billed: nil)
    query = create_query(bigquery_connection: connection, sql_body: "SELECT 1 AS n")
    execution = create_query_execution(query: query)

    stub_bigquery(rows: [ { n: 1 } ], fields: [ { name: "n", type: "INTEGER" } ])

    QueryExecutionJob.perform_now(execution)

    path = Pathname.new(ENV.fetch("BEAMS_CSV_PATH") { Rails.root.join("storage/csv").to_s }).join("#{execution.id}.csv.gz")
    assert File.exist?(path)
    csv = Zlib::GzipReader.open(path, &:read)
    assert_includes csv, "n"
    assert_includes csv, "1"
  end

  test "broadcasts the result" do
    connection = create_bigquery_connection(maximum_bytes_billed: nil)
    query = create_query(bigquery_connection: connection, sql_body: "SELECT 1 AS n")
    execution = create_query_execution(query: query)

    stub_bigquery(rows: [ { n: 1 } ], fields: [ { name: "n", type: "INTEGER" } ])

    QueryExecutionJob.perform_now(execution)

    assert @__broadcast_calls.any? { |e| e.id == execution.id },
      "expected broadcast_result to be called with execution(id=#{execution.id})"
  end

  test "passes the bound SQL and the connection job options to BigQuery" do
    connection = create_bigquery_connection(maximum_bytes_billed: 1_000_000)
    query = create_query(bigquery_connection: connection, sql_body: "SELECT 1 AS n")
    execution = create_query_execution(query: query)

    stubs = stub_bigquery(rows: [ { n: 1 } ], fields: [ { name: "n", type: "INTEGER" } ])

    QueryExecutionJob.perform_now(execution)

    call = stubs[:query_job_calls].first
    assert_equal query.bound_sql, call[:sql]
    assert_equal 1_000_000, call[:opts][:maximum_bytes_billed]
  end

  # --- failure path ---

  test "transitions to failed and records the error message" do
    connection = create_bigquery_connection(maximum_bytes_billed: nil)
    query = create_query(bigquery_connection: connection, sql_body: "SELECT 1 AS n")
    execution = create_query_execution(query: query)

    client = Object.new
    client.define_singleton_method(:query_job) { |*_args, **_opts| raise Google::Cloud::Error.new("invalid query") }
    install_bigquery_client(client)

    QueryExecutionJob.perform_now(execution)
    execution.reload

    assert_predicate execution, :failed?
    assert_includes execution.error_message, "invalid query"
    assert_predicate execution.finished_at, :present?
    assert @__broadcast_calls.any? { |e| e.id == execution.id }
  end

  test "marks failed when the BigQuery job itself reports failure" do
    connection = create_bigquery_connection(maximum_bytes_billed: nil)
    query = create_query(bigquery_connection: connection, sql_body: "SELECT 1 AS n")
    execution = create_query_execution(query: query)

    bq_job = Object.new
    bq_job.define_singleton_method(:wait_until_done!) { nil }
    bq_job.define_singleton_method(:failed?) { true }
    bq_job.define_singleton_method(:error) { { "message" => "quota exceeded" } }
    client = Object.new
    client.define_singleton_method(:query_job) { |*_args, **_opts| bq_job }
    install_bigquery_client(client)

    QueryExecutionJob.perform_now(execution)
    execution.reload

    assert_predicate execution, :failed?
    assert_includes execution.error_message, "quota exceeded"
  end

  # --- truncation ---

  test "truncates and marks result_truncated when over the row limit" do
    connection = create_bigquery_connection(maximum_bytes_billed: nil)
    query = create_query(bigquery_connection: connection, sql_body: "SELECT 1 AS n")
    execution = create_query_execution(query: query)

    rows = Array.new(10_001) { |i| { n: i } }
    stub_bigquery(rows: rows, fields: [ { name: "n", type: "INTEGER" } ])

    QueryExecutionJob.perform_now(execution)
    execution.reload

    assert_predicate execution, :succeeded?
    assert_equal true, execution.result_truncated
    assert_equal 10_000, execution.result[:rows].size
    # 全件は CSV に書かれる（行数 = 10,001 + ヘッダー）。
    path = Pathname.new(ENV.fetch("BEAMS_CSV_PATH") { Rails.root.join("storage/csv").to_s }).join("#{execution.id}.csv.gz")
    csv = Zlib::GzipReader.open(path, &:read)
    assert_equal 10_002, csv.lines.size
  end
end
