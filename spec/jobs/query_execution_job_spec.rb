require "rails_helper"
require "google/cloud/bigquery"

RSpec.describe QueryExecutionJob, type: :job do
  let(:connection) { create(:bigquery_connection, maximum_bytes_billed: nil) }
  let(:query) { create(:query, bigquery_connection: connection, sql_body: "SELECT 1 AS n") }
  let(:execution) { create(:query_execution, query: query) }

  # BigQuery クライアントと query_job をスタブする（実 API は呼ばない）。
  # data は Google::Cloud::Bigquery::Data 風: each で Hash 行を返し、
  # #fields で列スキーマ（name/type）を返す。
  def stub_bigquery(rows:, fields:)
    field_doubles = fields.map do |f|
      instance_double(Google::Cloud::Bigquery::Schema::Field, name: f[:name], type: f[:type])
    end
    data = instance_double(Google::Cloud::Bigquery::Data, fields: field_doubles)
    allow(data).to receive(:each) { |&blk| rows.each(&blk) }
    allow(data).to receive(:map) { |&blk| rows.map(&blk) }

    bq_job = instance_double(Google::Cloud::Bigquery::QueryJob)
    allow(bq_job).to receive(:wait_until_done!)
    allow(bq_job).to receive(:failed?).and_return(false)
    allow(bq_job).to receive(:data).and_return(data)

    client = instance_double(Google::Cloud::Bigquery::Project)
    allow(client).to receive(:query_job).and_return(bq_job)
    allow_any_instance_of(Bigquery::Connection).to receive(:bigquery).and_return(client)
    { client: client, job: bq_job, data: data }
  end

  before do
    FileUtils.rm_rf(Rails.root.join("storage/csv"))
    allow(QueryExecutionJob).to receive(:broadcast_result)
  end

  describe "success path" do
    it "transitions to succeeded and stores the compressed result" do
      stub_bigquery(
        rows: [ { n: 1 }, { n: 2 } ],
        fields: [ { name: "n", type: "INTEGER" } ]
      )

      QueryExecutionJob.perform_now(execution)
      execution.reload

      expect(execution).to be_succeeded
      expect(execution.started_at).to be_present
      expect(execution.finished_at).to be_present
      expect(execution.result_row_count).to eq(2)
      expect(execution.result_truncated).to be(false)
      result = execution.result
      expect(result[:schema]).to eq([ { "name" => "n", "type" => "INTEGER" } ])
      expect(result[:rows]).to eq([ [ 1 ], [ 2 ] ])
    end

    it "writes a gzip CSV file for the execution" do
      stub_bigquery(rows: [ { n: 1 } ], fields: [ { name: "n", type: "INTEGER" } ])

      QueryExecutionJob.perform_now(execution)

      path = Rails.root.join("storage/csv/#{execution.id}.csv.gz")
      expect(File).to exist(path)
      csv = Zlib::GzipReader.open(path, &:read)
      expect(csv).to include("n")
      expect(csv).to include("1")
    end

    it "broadcasts the result" do
      stub_bigquery(rows: [ { n: 1 } ], fields: [ { name: "n", type: "INTEGER" } ])

      QueryExecutionJob.perform_now(execution)

      expect(QueryExecutionJob).to have_received(:broadcast_result).with(
        an_object_having_attributes(id: execution.id)
      )
    end

    it "passes the bound SQL and the connection job options to BigQuery" do
      connection.update!(maximum_bytes_billed: 1_000_000)
      stubs = stub_bigquery(rows: [ { n: 1 } ], fields: [ { name: "n", type: "INTEGER" } ])

      QueryExecutionJob.perform_now(execution)

      expect(stubs[:client]).to have_received(:query_job).with(
        query.bound_sql, hash_including(maximum_bytes_billed: 1_000_000)
      )
    end
  end

  describe "failure path" do
    it "transitions to failed and records the error message" do
      client = instance_double(Google::Cloud::Bigquery::Project)
      allow(client).to receive(:query_job).and_raise(Google::Cloud::Error.new("invalid query"))
      allow_any_instance_of(Bigquery::Connection).to receive(:bigquery).and_return(client)

      QueryExecutionJob.perform_now(execution)
      execution.reload

      expect(execution).to be_failed
      expect(execution.error_message).to include("invalid query")
      expect(execution.finished_at).to be_present
      expect(QueryExecutionJob).to have_received(:broadcast_result)
        .with(an_object_having_attributes(id: execution.id))
    end

    it "marks failed when the BigQuery job itself reports failure" do
      bq_job = instance_double(Google::Cloud::Bigquery::QueryJob)
      allow(bq_job).to receive(:wait_until_done!)
      allow(bq_job).to receive(:failed?).and_return(true)
      gcs_error = instance_double("error", message: "quota exceeded")
      allow(bq_job).to receive(:error).and_return({ "message" => "quota exceeded" })
      client = instance_double(Google::Cloud::Bigquery::Project)
      allow(client).to receive(:query_job).and_return(bq_job)
      allow_any_instance_of(Bigquery::Connection).to receive(:bigquery).and_return(client)

      QueryExecutionJob.perform_now(execution)
      execution.reload

      expect(execution).to be_failed
      expect(execution.error_message).to include("quota exceeded")
    end
  end

  describe "truncation" do
    it "truncates and marks result_truncated when over the row limit" do
      rows = Array.new(10_001) { |i| { n: i } }
      stub_bigquery(rows: rows, fields: [ { name: "n", type: "INTEGER" } ])

      QueryExecutionJob.perform_now(execution)
      execution.reload

      expect(execution).to be_succeeded
      expect(execution.result_truncated).to be(true)
      expect(execution.result[:rows].size).to eq(10_000)
      # 全件は CSV に書かれる（行数 = 10,001 + ヘッダー）。
      path = Rails.root.join("storage/csv/#{execution.id}.csv.gz")
      csv = Zlib::GzipReader.open(path, &:read)
      expect(csv.lines.size).to eq(10_002)
    end
  end
end
