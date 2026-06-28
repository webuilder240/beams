require "test_helper"
require "securerandom"

class QueryResultTest < ActiveSupport::TestCase
  SCHEMA = [ { "name" => "n", "type" => "INTEGER" } ].freeze

  # --- #truncate (row-count limit) ---
  test "keeps all rows and is not truncated under the row limit" do
    rows = Array.new(10) { |i| [ i ] }
    result = QueryResult.new(schema: SCHEMA, rows: rows).truncate
    assert_equal 10, result[:rows].size
    assert_not result[:truncated]
    assert_equal SCHEMA, result[:schema]
  end

  test "keeps exactly 10,000 rows without truncating at the boundary" do
    rows = Array.new(10_000) { |i| [ i ] }
    result = QueryResult.new(schema: SCHEMA, rows: rows).truncate
    assert_equal 10_000, result[:rows].size
    assert_not result[:truncated]
  end

  test "truncates to 10,000 rows when given 10,001 rows" do
    rows = Array.new(10_001) { |i| [ i ] }
    result = QueryResult.new(schema: SCHEMA, rows: rows).truncate
    assert_equal 10_000, result[:rows].size
    assert result[:truncated]
    # 先頭 N 行であること。
    assert_equal [ 0 ], result[:rows].first
    assert_equal [ 9_999 ], result[:rows].last
  end

  # --- #truncate (compressed-size limit) ---
  test "truncates further when the compressed blob exceeds 10MB" do
    # 各行を非圧縮性（ランダム）の大きな値にして、10,000 行未満でも
    # 圧縮後 10MB を超えるようにする（8,000 行 ≒ 17MB）。
    rows = Array.new(8_000) { |i| [ i, SecureRandom.hex(2_000) ] }
    result = QueryResult.new(schema: SCHEMA, rows: rows).truncate
    assert result[:truncated]
    assert result[:rows].size < 8_000

    compressed = Zlib::Deflate.deflate(JSON.generate(schema: SCHEMA, rows: result[:rows]))
    assert compressed.bytesize <= QueryResult::MAX_COMPRESSED_BYTES
  end

  test "does not truncate small payloads on size" do
    rows = Array.new(100) { |i| [ i ] }
    result = QueryResult.new(schema: SCHEMA, rows: rows).truncate
    assert_not result[:truncated]
    assert_equal 100, result[:rows].size
  end
end
