require "json"
require "zlib"

# クエリの非同期実行1回ぶんを表す（トピック10）。`Query` 配下のフラットな
# トップレベルモデル。結果は最新成功1件のみ保持（上書き・履歴なし）し、
# 表示用の先頭 N 行＋列スキーマを JSON + gzip 圧縮して `result_blob` に格納する。
class QueryExecution < ApplicationRecord
  belongs_to :query

  enum :status, {
    pending: "pending",
    running: "running",
    succeeded: "succeeded",
    failed: "failed"
  }

  validates :status, presence: true

  # 表示用の結果（列スキーマ＋行データ）を JSON 化し `Zlib::Deflate`（gzip）で
  # 圧縮して `result_blob` に書き込む。文字列の二重持ちを避け 1 レコードに集約する。
  def store_result(schema, rows)
    json = JSON.generate(schema: schema, rows: rows)
    self.result_blob = Zlib::Deflate.deflate(json)
  end

  # `result_blob` を展開して `{ schema: Array, rows: Array }` を返す。
  # blob が未保存なら nil。
  def result
    return nil if result_blob.blank?

    parsed = JSON.parse(Zlib::Inflate.inflate(result_blob))
    { schema: parsed["schema"], rows: parsed["rows"] }
  end
end
