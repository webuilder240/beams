require "test_helper"

class Bigquery::ConnectionTest < ActiveSupport::TestCase
  include ActiveSupport::Testing::TimeHelpers

  # 簡易なフェイクBigQueryクライアント。RSpec の instance_double と同じ用途。
  # 渡したブロック／値で query_job / datasets / query を応答させ、呼び出し回数を記録する。
  class FakeBigqueryClient
    attr_reader :query_job_calls, :datasets_calls, :query_calls

    def initialize(query_job: nil, datasets: nil, query: nil,
                   query_job_proc: nil, datasets_proc: nil, query_proc: nil)
      @query_job = query_job
      @datasets = datasets
      @query = query
      @query_job_proc = query_job_proc
      @datasets_proc = datasets_proc
      @query_proc = query_proc
      @query_job_calls = []
      @datasets_calls = 0
      @query_calls = []
    end

    def query_job(sql, **opts)
      @query_job_calls << [ sql, opts ]
      return @query_job_proc.call(sql, **opts) if @query_job_proc
      @query_job
    end

    def datasets(**opts)
      @datasets_calls += 1
      return @datasets_proc.call(**opts) if @datasets_proc
      @datasets
    end

    def query(sql, **opts)
      @query_calls << [ sql, opts ]
      return @query_proc.call(sql, **opts) if @query_proc
      @query
    end
  end

  # --- table mapping (namespace) ---
  test "maps to the bigquery_connections table via table_name_prefix" do
    assert_equal "bigquery_connections", Bigquery::Connection.table_name
  end

  # --- validations ---
  test "is valid with the factory" do
    assert build_bigquery_connection.valid?
  end

  test "requires a name" do
    connection = build_bigquery_connection(name: nil)
    assert_not connection.valid?
    assert_predicate connection.errors[:name], :present?
  end

  test "requires a project_id" do
    connection = build_bigquery_connection(project_id: nil)
    assert_not connection.valid?
    assert_predicate connection.errors[:project_id], :present?
  end

  test "rejects a project_id with invalid characters" do
    connection = build_bigquery_connection(project_id: "invalid project!")
    assert_not connection.valid?
    assert_predicate connection.errors[:project_id], :present?
  end

  test "accepts a project_id with alphanumerics and hyphens" do
    connection = build_bigquery_connection(project_id: "my-project-123")
    assert connection.valid?
  end

  test "requires service_account_json" do
    connection = build_bigquery_connection(service_account_json: nil)
    assert_not connection.valid?
    assert_predicate connection.errors[:service_account_json], :present?
  end

  test "rejects service_account_json that is not parseable JSON" do
    connection = build_bigquery_connection(service_account_json: "{not valid json")
    assert_not connection.valid?
    assert_predicate connection.errors[:service_account_json], :present?
  end

  test "rejects service_account_json that is valid JSON but not an object" do
    connection = build_bigquery_connection(service_account_json: "[1, 2, 3]")
    assert_not connection.valid?
    assert_predicate connection.errors[:service_account_json], :present?
  end

  test "allows a nil maximum_bytes_billed (= no limit)" do
    connection = build_bigquery_connection(maximum_bytes_billed: nil)
    assert connection.valid?
  end

  test "allows a positive maximum_bytes_billed" do
    connection = build_bigquery_connection(maximum_bytes_billed: 1_000_000)
    assert connection.valid?
  end

  test "rejects a zero maximum_bytes_billed" do
    connection = build_bigquery_connection(maximum_bytes_billed: 0)
    assert_not connection.valid?
    assert_predicate connection.errors[:maximum_bytes_billed], :present?
  end

  test "rejects a negative maximum_bytes_billed" do
    connection = build_bigquery_connection(maximum_bytes_billed: -1)
    assert_not connection.valid?
    assert_predicate connection.errors[:maximum_bytes_billed], :present?
  end

  # --- service_account_json storage (plaintext) ---
  test "returns the original plaintext via the attribute reader" do
    json = '{"type":"service_account","project_id":"p"}'
    connection = create_bigquery_connection(service_account_json: json)
    assert_equal json, connection.reload.service_account_json
  end

  test "stores the plaintext as-is in the raw SQLite row" do
    secret = "SUPER_SECRET_PRIVATE_KEY_MARKER"
    json = %({"type":"service_account","private_key":"#{secret}"})
    connection = create_bigquery_connection(service_account_json: json)

    raw = ActiveRecord::Base.connection.select_value(
      "SELECT service_account_json FROM bigquery_connections WHERE id = #{connection.id}"
    )
    assert_equal json, raw
    assert_includes raw, secret
  end

  # --- #bigquery ---
  test "returns a Google::Cloud::Bigquery client built from project_id and credentials" do
    connection = build_bigquery_connection(project_id: "my-project-123", service_account_json: '{"type":"service_account","project_id":"my-project-123"}')
    fake_client = Object.new
    received_args = nil
    stub = lambda do |**kwargs|
      received_args = kwargs
      fake_client
    end
    Google::Cloud::Bigquery.stub(:new, stub) do
      assert_equal fake_client, connection.bigquery
    end
    assert_equal "my-project-123", received_args[:project_id]
    assert_equal({ "type" => "service_account", "project_id" => "my-project-123" }, received_args[:credentials])
  end

  test "memoizes the client" do
    connection = build_bigquery_connection(project_id: "my-project-123", service_account_json: '{"type":"service_account","project_id":"my-project-123"}')
    fake_client = Object.new
    call_count = 0
    stub = lambda do |**_kwargs|
      call_count += 1
      fake_client
    end
    Google::Cloud::Bigquery.stub(:new, stub) do
      connection.bigquery
      connection.bigquery
    end
    assert_equal 1, call_count
  end

  # --- #test_connection ---
  test "returns success: true when both dry-run and datasets.list succeed" do
    connection = build_bigquery_connection
    fake_client = FakeBigqueryClient.new(query_job: nil, datasets: [])
    connection.stub(:bigquery, fake_client) do
      assert_equal({ success: true }, connection.test_connection)
    end
  end

  test "treats an empty dataset list as success" do
    connection = build_bigquery_connection
    fake_client = FakeBigqueryClient.new(query_job: nil, datasets: [])
    connection.stub(:bigquery, fake_client) do
      result = connection.test_connection
      assert_equal true, result[:success]
    end
  end

  test "runs the dry-run query without billing (dry_run: true)" do
    connection = build_bigquery_connection
    fake_client = FakeBigqueryClient.new(query_job: nil, datasets: [])
    connection.stub(:bigquery, fake_client) do
      connection.test_connection
    end
    assert_equal 1, fake_client.query_job_calls.size
    sql, opts = fake_client.query_job_calls.first
    assert_equal "SELECT 1", sql
    assert_equal true, opts[:dryrun]
  end

  test "extracts the missing permission and returns failure when dry-run is denied for bigquery.jobs.create" do
    connection = build_bigquery_connection
    error = Google::Cloud::PermissionDeniedError.new(
      "Access Denied: Project p: User does not have bigquery.jobs.create permission in project p."
    )
    fake_client = FakeBigqueryClient.new(
      query_job_proc: ->(_sql, **_opts) { raise error },
      datasets: []
    )
    connection.stub(:bigquery, fake_client) do
      result = connection.test_connection
      assert_equal false, result[:success]
      assert_includes result[:missing_permissions], "bigquery.jobs.create"
      assert_predicate result[:message], :present?
    end
  end

  test "extracts the missing permission and returns failure when datasets.list is denied" do
    connection = build_bigquery_connection
    error = Google::Cloud::PermissionDeniedError.new(
      "Access Denied: Project p: User does not have bigquery.datasets.list permission."
    )
    fake_client = FakeBigqueryClient.new(
      query_job: nil,
      datasets_proc: ->(**_opts) { raise error }
    )
    connection.stub(:bigquery, fake_client) do
      result = connection.test_connection
      assert_equal false, result[:success]
      assert_includes result[:missing_permissions], "bigquery.datasets.list"
    end
  end

  test "aggregates the missing permissions across both checks" do
    connection = build_bigquery_connection
    jobs_error = Google::Cloud::PermissionDeniedError.new(
      "User does not have bigquery.jobs.create permission in project p."
    )
    datasets_error = Google::Cloud::PermissionDeniedError.new(
      "User does not have bigquery.datasets.list permission."
    )
    fake_client = FakeBigqueryClient.new(
      query_job_proc: ->(_sql, **_opts) { raise jobs_error },
      datasets_proc: ->(**_opts) { raise datasets_error }
    )
    connection.stub(:bigquery, fake_client) do
      result = connection.test_connection
      assert_equal [ "bigquery.jobs.create", "bigquery.datasets.list" ].sort, result[:missing_permissions].sort
    end
  end

  test "returns failure with the error message and no missing permissions for a non-permission error" do
    connection = build_bigquery_connection
    fake_client = FakeBigqueryClient.new(
      query_job_proc: ->(_sql, **_opts) { raise Google::Cloud::Error.new("network unreachable") },
      datasets: []
    )
    connection.stub(:bigquery, fake_client) do
      result = connection.test_connection
      assert_equal false, result[:success]
      assert_equal [], result[:missing_permissions]
      assert_includes result[:message], "network unreachable"
    end
  end

  # --- maximum_bytes_billed_gb (GB 入力 → bytes 保存の仮想属性) ---
  test "writes GB input as bytes into maximum_bytes_billed" do
    connection = build_bigquery_connection
    connection.maximum_bytes_billed_gb = "10"
    assert_equal 10 * (1024**3), connection.maximum_bytes_billed
  end

  test "reads the bytes back as GB" do
    connection = build_bigquery_connection(maximum_bytes_billed: 5 * (1024**3))
    assert_equal 5.0, connection.maximum_bytes_billed_gb
  end

  test "treats a blank GB input as no limit (nil)" do
    connection = build_bigquery_connection(maximum_bytes_billed: 10**10)
    connection.maximum_bytes_billed_gb = ""
    assert_nil connection.maximum_bytes_billed
  end

  test "returns nil GB when no limit is set" do
    connection = build_bigquery_connection(maximum_bytes_billed: nil)
    assert_nil connection.maximum_bytes_billed_gb
  end

  test "accepts a fractional GB value" do
    connection = build_bigquery_connection
    connection.maximum_bytes_billed_gb = "0.5"
    assert_equal (0.5 * (1024**3)).round, connection.maximum_bytes_billed
  end

  # --- #over_limit? ---
  test "is false when maximum_bytes_billed is nil (no limit)" do
    connection = build_bigquery_connection(maximum_bytes_billed: nil)
    assert_equal false, connection.over_limit?(10**12)
  end

  test "is false when bytes_processed is within the limit" do
    connection = build_bigquery_connection(maximum_bytes_billed: 1_000)
    assert_equal false, connection.over_limit?(999)
  end

  test "is false when bytes_processed equals the limit (boundary)" do
    connection = build_bigquery_connection(maximum_bytes_billed: 1_000)
    assert_equal false, connection.over_limit?(1_000)
  end

  test "is true when bytes_processed exceeds the limit" do
    connection = build_bigquery_connection(maximum_bytes_billed: 1_000)
    assert_equal true, connection.over_limit?(1_001)
  end

  # --- #job_options ---
  test "includes maximum_bytes_billed when a limit is set" do
    connection = build_bigquery_connection(maximum_bytes_billed: 5_000)
    assert_equal({ maximum_bytes_billed: 5_000 }, connection.job_options)
  end

  test "is empty when no limit is set (nil)" do
    connection = build_bigquery_connection(maximum_bytes_billed: nil)
    assert_equal({}, connection.job_options)
  end

  # --- #dry_run_job ---
  test "creates a dry-run job carrying the connection's maximum_bytes_billed" do
    connection = build_bigquery_connection(maximum_bytes_billed: 5_000)
    job = Object.new
    fake_client = FakeBigqueryClient.new(query_job: job)
    connection.stub(:bigquery, fake_client) do
      assert_equal job, connection.dry_run_job("SELECT 1")
    end
    sql, opts = fake_client.query_job_calls.first
    assert_equal "SELECT 1", sql
    assert_equal true, opts[:dryrun]
    assert_equal 5_000, opts[:maximum_bytes_billed]
  end

  test "omits maximum_bytes_billed when no limit is set" do
    connection = build_bigquery_connection(maximum_bytes_billed: nil)
    job = Object.new
    fake_client = FakeBigqueryClient.new(query_job: job)
    connection.stub(:bigquery, fake_client) do
      assert_equal job, connection.dry_run_job("SELECT 1")
    end
    sql, opts = fake_client.query_job_calls.first
    assert_equal "SELECT 1", sql
    assert_equal true, opts[:dryrun]
    assert_not opts.key?(:maximum_bytes_billed)
  end

  # --- schema cache (SolidCache) ---
  # BigQuery のレスポンスをスタブする double 群を組み立てる。
  # datasets.list → dataset.tables → INFORMATION_SCHEMA.COLUMNS の3段。
  def default_columns
    [
      { table_name: "events", column_name: "user_id",
        data_type: "STRING", is_nullable: "YES", ordinal_position: 1 },
      { table_name: "events", column_name: "amount",
        data_type: "INT64", is_nullable: "NO", ordinal_position: 2 }
    ]
  end

  def build_fake_dataset
    table = Struct.new(:table_id, :type).new("events", "TABLE")
    Struct.new(:dataset_id, :name, :tables).new("analytics", "Analytics", [ table ])
  end

  def stub_bigquery_for(connection, columns: default_columns)
    fake_client = FakeBigqueryClient.new(datasets: [ build_fake_dataset ], query: columns)
    [ fake_client, ->(blk) { connection.stub(:bigquery, fake_client) { blk.call(fake_client) } } ]
  end

  test "fetches datasets, tables and columns from BigQuery and writes the cache" do
    Rails.cache.clear
    connection = create_bigquery_connection
    fake_client = FakeBigqueryClient.new(datasets: [ build_fake_dataset ], query: default_columns)

    structure = nil
    connection.stub(:bigquery, fake_client) do
      structure = connection.sync_schema!
    end

    assert_operator fake_client.datasets_calls, :>=, 1
    assert_operator fake_client.query_calls.size, :>=, 1

    dataset = structure[:datasets].first
    assert_equal "analytics", dataset[:dataset_id]
    assert_equal "Analytics", dataset[:name]

    table = dataset[:tables].first
    assert_equal "events", table[:table_id]
    assert_equal "TABLE", table[:table_type]

    columns = table[:columns]
    assert_equal [ "user_id", "amount" ], columns.map { |c| c[:column_name] }
    assert_equal "user_id", columns.first[:column_name]
    assert_equal "STRING", columns.first[:data_type]
    assert_equal true, columns.first[:is_nullable]
    assert_equal 1, columns.first[:ordinal_position]
    assert_equal false, columns.second[:is_nullable]
  end

  test "stores the structure in Rails.cache under the connection-scoped key" do
    Rails.cache.clear
    connection = create_bigquery_connection
    fake_client = FakeBigqueryClient.new(datasets: [ build_fake_dataset ], query: default_columns)

    connection.stub(:bigquery, fake_client) do
      connection.sync_schema!
    end

    cached = Rails.cache.read("bigquery:schema:#{connection.id}")
    assert_predicate cached, :present?
    assert_equal "analytics", cached[:datasets].first[:dataset_id]
    assert_predicate cached[:fetched_at], :present?
  end

  test "syncs on the first access and serves from cache on the second" do
    Rails.cache.clear
    connection = create_bigquery_connection
    fake_client = FakeBigqueryClient.new(datasets: [ build_fake_dataset ], query: default_columns)

    first = nil
    second = nil
    connection.stub(:bigquery, fake_client) do
      first = connection.cached_schema
      second = connection.cached_schema
    end

    assert_equal "analytics", first[:datasets].first[:dataset_id]
    assert_equal first, second
    assert_equal 1, fake_client.datasets_calls
  end

  test "re-fetches after the 24h TTL expires" do
    Rails.cache.clear
    connection = create_bigquery_connection
    fake_client = FakeBigqueryClient.new(datasets: [ build_fake_dataset ], query: default_columns)

    connection.stub(:bigquery, fake_client) do
      connection.cached_schema

      travel 25.hours do
        connection.cached_schema
      end
    end

    assert_equal 2, fake_client.datasets_calls
  end

  test "serves from cache within the TTL (1 hour later)" do
    Rails.cache.clear
    connection = create_bigquery_connection
    fake_client = FakeBigqueryClient.new(datasets: [ build_fake_dataset ], query: default_columns)

    connection.stub(:bigquery, fake_client) do
      connection.cached_schema

      travel 1.hour do
        connection.cached_schema
      end
    end

    assert_equal 1, fake_client.datasets_calls
  end

  test "re-fetches and overwrites even when a fresh cache exists" do
    Rails.cache.clear
    connection = create_bigquery_connection
    fake_client = FakeBigqueryClient.new(datasets: [ build_fake_dataset ], query: default_columns)

    connection.stub(:bigquery, fake_client) do
      connection.cached_schema
      connection.sync_schema!(force: true)
    end

    assert_equal 2, fake_client.datasets_calls
  end
end
