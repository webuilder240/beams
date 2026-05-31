require "json"
require "zlib"

# クエリの非同期実行1回ぶんを表す（トピック10）。`Query` 配下のフラットな
# トップレベルモデル。実行ごとに 1 レコードを永続化し、各レコードが自分の
# 表示用結果（先頭 N 行＋列スキーマを JSON + gzip 圧縮した `result_blob`）を
# 個別に保持する。これにより過去の実行履歴と結果テーブルを後から再表示できる
# （トピック17）。CSV も `storage/csv/<execution.id>.csv.gz` と実行 ID ごとに残る。
class QueryExecution < ApplicationRecord
  belongs_to :query

  enum :status, {
    pending: "pending",
    running: "running",
    succeeded: "succeeded",
    failed: "failed"
  }

  validates :status, presence: true

  # 実行履歴の取得用スコープ。新しい順（作成日時の降順）。詳細ページの履歴一覧で
  # `limit(N)` と組み合わせて直近 N 件を表示する。
  scope :recent, -> { order(created_at: :desc) }

  # started_at→finished_at の所要時間（秒・Float）。どちらか欠けていれば nil。
  def duration
    return nil if started_at.blank? || finished_at.blank?

    finished_at - started_at
  end

  # 成功実行かつ表示用の結果 blob を保持しているか。履歴一覧で「結果を表示」
  # リンクや CSV リンクを出すかどうかの判定に使う。
  def succeeded_with_result?
    succeeded? && result_blob.present?
  end

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
