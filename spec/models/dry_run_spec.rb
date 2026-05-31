require "rails_helper"

RSpec.describe DryRun, type: :model do
  let(:connection) { build(:bigquery_connection) }
  let(:fake_client) { instance_double(Google::Cloud::Bigquery::Project) }

  before do
    allow(connection).to receive(:bigquery).and_return(fake_client)
  end

  # dry-run の QueryJob をスタブする double を組み立てる。
  # google-cloud-bigquery はスキャン予定量を QueryJob#bytes_processed で返す。
  def stub_job(bytes:)
    instance_double(Google::Cloud::Bigquery::QueryJob, bytes_processed: bytes)
  end

  describe "#call" do
    it "runs a dry-run job and returns the scanned bytes" do
      job = stub_job(bytes: 5_368_709_120)
      allow(connection).to receive(:dry_run_job)
        .with("SELECT 1").and_return(job)

      result = described_class.new(connection, "SELECT 1").call

      expect(result).to eq({ bytes_processed: 5_368_709_120 })
    end

    it "delegates job creation to the connection (which applies maximum_bytes_billed)" do
      job = stub_job(bytes: 42)
      allow(connection).to receive(:dry_run_job).and_return(job)

      described_class.new(connection, "SELECT * FROM t").call

      expect(connection).to have_received(:dry_run_job).with("SELECT * FROM t")
    end

    it "coerces a nil total_bytes_processed to 0" do
      job = stub_job(bytes: nil)
      allow(connection).to receive(:dry_run_job).and_return(job)

      result = described_class.new(connection, "SELECT 1").call

      expect(result).to eq({ bytes_processed: 0 })
    end

    it "lets BigQuery errors propagate (caller handles them)" do
      allow(connection).to receive(:dry_run_job)
        .and_raise(Google::Cloud::Error.new("invalid query"))

      expect {
        described_class.new(connection, "SELECT bad").call
      }.to raise_error(Google::Cloud::Error, "invalid query")
    end
  end
end
