require "rails_helper"

RSpec.describe QueryExecution, type: :model do
  describe "associations" do
    it "belongs to a query" do
      execution = build(:query_execution)
      expect(execution.query).to be_a(Query)
    end

    it "is destroyed when its query is destroyed" do
      execution = create(:query_execution)
      query = execution.query
      expect { query.destroy }.to change(QueryExecution, :count).by(-1)
    end
  end

  describe "enum status" do
    it "defines pending/running/succeeded/failed" do
      expect(described_class.statuses).to eq(
        "pending" => "pending",
        "running" => "running",
        "succeeded" => "succeeded",
        "failed" => "failed"
      )
    end

    it "defaults to pending" do
      expect(build(:query_execution).status).to eq("pending")
    end

    it "supports the predicate and bang transitions" do
      execution = create(:query_execution)
      execution.running!
      expect(execution).to be_running
      execution.succeeded!
      expect(execution).to be_succeeded
      execution.failed!
      expect(execution).to be_failed
    end

    it "raises on an unknown status" do
      expect { build(:query_execution, status: "bogus") }
        .to raise_error(ArgumentError)
    end
  end

  describe "validations" do
    it "requires a status" do
      execution = build(:query_execution)
      execution.status = nil
      expect(execution).not_to be_valid
      expect(execution.errors[:status]).to be_present
    end
  end

  describe ".recent" do
    it "orders executions by created_at descending (newest first)" do
      query = create(:query)
      older = create(:query_execution, query: query, created_at: 2.hours.ago)
      newer = create(:query_execution, query: query, created_at: 1.hour.ago)
      newest = create(:query_execution, query: query, created_at: Time.current)

      expect(query.query_executions.recent.to_a).to eq([ newest, newer, older ])
    end
  end

  describe "#duration" do
    it "returns the elapsed seconds between started_at and finished_at" do
      execution = build(:query_execution,
                        started_at: Time.utc(2026, 5, 31, 12, 0, 0),
                        finished_at: Time.utc(2026, 5, 31, 12, 0, 3))
      expect(execution.duration).to eq(3.0)
    end

    it "returns nil when started_at is missing" do
      expect(build(:query_execution, started_at: nil, finished_at: Time.current).duration).to be_nil
    end

    it "returns nil when finished_at is missing" do
      expect(build(:query_execution, started_at: Time.current, finished_at: nil).duration).to be_nil
    end
  end

  describe "#succeeded_with_result?" do
    it "is true for a succeeded execution that has a result blob" do
      execution = create(:query_execution, :succeeded)
      execution.store_result([ { "name" => "n", "type" => "INTEGER" } ], [ [ 1 ] ])
      execution.save!
      expect(execution).to be_succeeded_with_result
    end

    it "is false for a succeeded execution without a result blob" do
      execution = create(:query_execution, :succeeded)
      expect(execution).not_to be_succeeded_with_result
    end

    it "is false for a failed execution even with a blob" do
      execution = create(:query_execution, :failed)
      execution.store_result([ { "name" => "n", "type" => "INTEGER" } ], [ [ 1 ] ])
      execution.save!
      expect(execution).not_to be_succeeded_with_result
    end
  end

  describe "#store_result and #result (JSON + gzip round trip)" do
    let(:execution) { create(:query_execution) }
    let(:schema) { [ { "name" => "id", "type" => "INTEGER" }, { "name" => "name", "type" => "STRING" } ] }
    let(:rows) { [ [ 1, "alice" ], [ 2, "bob" ] ] }

    it "writes a gzip-compressed JSON blob to result_blob" do
      execution.store_result(schema, rows)
      expect(execution.result_blob).to be_present
      # 圧縮されているので生の JSON 文字列とは一致しない（バイナリ）。
      expect(execution.result_blob).not_to include("alice")
      # gzip(deflate) ストリームとして展開できる。
      inflated = Zlib::Inflate.inflate(execution.result_blob)
      expect(JSON.parse(inflated)).to eq("schema" => schema, "rows" => rows)
    end

    it "round-trips back to { schema:, rows: } via #result" do
      execution.store_result(schema, rows)
      result = execution.result
      expect(result[:schema]).to eq(schema)
      expect(result[:rows]).to eq(rows)
    end

    it "returns nil from #result when no blob is stored" do
      expect(execution.result).to be_nil
    end
  end
end
