require "rails_helper"
require "securerandom"

RSpec.describe QueryResult, type: :model do
  let(:schema) { [ { "name" => "n", "type" => "INTEGER" } ] }

  describe "#truncate (row-count limit)" do
    it "keeps all rows and is not truncated under the row limit" do
      rows = Array.new(10) { |i| [ i ] }
      result = described_class.new(schema: schema, rows: rows).truncate
      expect(result[:rows].size).to eq(10)
      expect(result[:truncated]).to be(false)
      expect(result[:schema]).to eq(schema)
    end

    it "keeps exactly 10,000 rows without truncating at the boundary" do
      rows = Array.new(10_000) { |i| [ i ] }
      result = described_class.new(schema: schema, rows: rows).truncate
      expect(result[:rows].size).to eq(10_000)
      expect(result[:truncated]).to be(false)
    end

    it "truncates to 10,000 rows when given 10,001 rows" do
      rows = Array.new(10_001) { |i| [ i ] }
      result = described_class.new(schema: schema, rows: rows).truncate
      expect(result[:rows].size).to eq(10_000)
      expect(result[:truncated]).to be(true)
      # 先頭 N 行であること。
      expect(result[:rows].first).to eq([ 0 ])
      expect(result[:rows].last).to eq([ 9_999 ])
    end
  end

  describe "#truncate (compressed-size limit)" do
    it "truncates further when the compressed blob exceeds 10MB" do
      # 各行を非圧縮性（ランダム）の大きな値にして、10,000 行未満でも
      # 圧縮後 10MB を超えるようにする（8,000 行 ≒ 17MB）。
      rows = Array.new(8_000) { |i| [ i, SecureRandom.hex(2_000) ] }
      result = described_class.new(schema: schema, rows: rows).truncate
      expect(result[:truncated]).to be(true)
      expect(result[:rows].size).to be < 8_000

      compressed = Zlib::Deflate.deflate(JSON.generate(schema: schema, rows: result[:rows]))
      expect(compressed.bytesize).to be <= QueryResult::MAX_COMPRESSED_BYTES
    end

    it "does not truncate small payloads on size" do
      rows = Array.new(100) { |i| [ i ] }
      result = described_class.new(schema: schema, rows: rows).truncate
      expect(result[:truncated]).to be(false)
      expect(result[:rows].size).to eq(100)
    end
  end
end
