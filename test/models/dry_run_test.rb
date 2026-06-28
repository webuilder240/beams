require "test_helper"

class DryRunTest < ActiveSupport::TestCase
  # dry-run の QueryJob をスタブする double を組み立てる。
  # google-cloud-bigquery はスキャン予定量を QueryJob#bytes_processed で返す。
  def stub_job(bytes:)
    Struct.new(:bytes_processed).new(bytes)
  end

  # --- #call ---
  test "runs a dry-run job and returns the scanned bytes" do
    connection = build_bigquery_connection
    job = stub_job(bytes: 5_368_709_120)
    connection.stub(:dry_run_job, ->(sql) { job }) do
      result = DryRun.new(connection, "SELECT 1").call
      assert_equal({ bytes_processed: 5_368_709_120 }, result)
    end
  end

  test "delegates job creation to the connection (which applies maximum_bytes_billed)" do
    connection = build_bigquery_connection
    job = stub_job(bytes: 42)
    received_sql = nil
    connection.stub(:dry_run_job, ->(sql) { received_sql = sql; job }) do
      DryRun.new(connection, "SELECT * FROM t").call
    end
    assert_equal "SELECT * FROM t", received_sql
  end

  test "coerces a nil total_bytes_processed to 0" do
    connection = build_bigquery_connection
    job = stub_job(bytes: nil)
    connection.stub(:dry_run_job, ->(sql) { job }) do
      result = DryRun.new(connection, "SELECT 1").call
      assert_equal({ bytes_processed: 0 }, result)
    end
  end

  test "lets BigQuery errors propagate (caller handles them)" do
    connection = build_bigquery_connection
    raiser = ->(sql) { raise Google::Cloud::Error.new("invalid query") }
    connection.stub(:dry_run_job, raiser) do
      error = assert_raises(Google::Cloud::Error) do
        DryRun.new(connection, "SELECT bad").call
      end
      assert_equal "invalid query", error.message
    end
  end
end
