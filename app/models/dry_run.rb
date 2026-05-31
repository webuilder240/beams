# BigQuery の dry-run を実行し、スキャン予定バイト数を返す純粋 PORO（`*Service` 禁止）。
#
# 課金ゼロ（`dry_run: true`）でジョブを投入し、`statistics.total_bytes_processed`
# を取り出す。ジョブ生成（および接続の `maximum_bytes_billed` 付与）は
# `Bigquery::Connection#dry_run_job` に委譲する（ジョブオプション組み立ての一元化）。
#
# BigQuery API 呼び出しはテストでスタブする。API エラーは握りつぶさず
# 呼び出し側（コントローラ）に伝播させる。
class DryRun
  def initialize(connection, sql)
    @connection = connection
    @sql = sql
  end

  # `{ bytes_processed: Integer }` を返す。
  # `google-cloud-bigquery` の dry-run（`QueryJob`）はスキャン予定量を
  # `QueryJob#bytes_processed` で返す。
  def call
    job = @connection.dry_run_job(@sql)
    { bytes_processed: job.bytes_processed.to_i }
  end
end
