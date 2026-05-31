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
