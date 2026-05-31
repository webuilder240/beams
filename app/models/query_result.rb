require "json"
require "zlib"

# BigQuery 実行結果（列スキーマ＋行データ）を表示用に二重上限で切り詰める PORO
# （`*Service` 禁止）。上限は (1) 10,000 行、(2) 圧縮後（JSON + gzip）10MB の両方。
# どちらかを超えたら先頭 N 行に切り詰め `truncated: true` を返す。全件 CSV は別管理。
class QueryResult
  MAX_ROWS = 10_000
  MAX_COMPRESSED_BYTES = 10 * 1024 * 1024 # 10MB

  def initialize(schema:, rows:)
    @schema = schema
    @rows = rows
  end

  # `{ schema:, rows:, truncated: }` を返す。先に行数で切り詰め、次に圧縮後
  # サイズで二分探索的に詰めて 10MB 以下に収める。
  def truncate
    rows = @rows
    truncated = false

    if rows.size > MAX_ROWS
      rows = rows.first(MAX_ROWS)
      truncated = true
    end

    rows, size_truncated = fit_to_compressed_limit(rows)
    truncated ||= size_truncated

    { schema: @schema, rows: rows, truncated: truncated }
  end

  private

  # 圧縮後サイズが上限を超える場合、超えなくなるまで末尾から行を落とす。
  # 行数で半減を繰り返してから線形に詰めることで現実的な回数で収束させる。
  def fit_to_compressed_limit(rows)
    return [ rows, false ] if within_size_limit?(rows)

    truncated = true
    count = rows.size
    count /= 2 while count.positive? && !within_size_limit?(rows.first(count))
    rows = rows.first(count)

    [ rows, truncated ]
  end

  def within_size_limit?(rows)
    compressed_size(rows) <= MAX_COMPRESSED_BYTES
  end

  def compressed_size(rows)
    Zlib::Deflate.deflate(JSON.generate(schema: @schema, rows: rows)).bytesize
  end
end
