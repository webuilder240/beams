require "csv"
require "zlib"

# クエリの非同期実行ジョブ（トピック10・SolidQueue）。
#
# フロー:
#   1. running! に更新（started_at 記録）
#   2. Query#bound_sql（{{name}}→@name）＋パラメータ（permit/missing/to_bigquery_param）
#   3. connection.bigquery.query_job(sql, params:, **job_options) でジョブ投入
#   4. wait_until_done! で完了待ち（ワーカースレッドはブロックしてよい）
#   5. 全件 CSV を storage/csv/<id>.csv.gz に書き出す（最新1件のみ保持）
#   6. QueryResult で二重上限（10,000行 / 圧縮後10MB）切り詰め → store_result
#   7. succeeded! に更新・blob 保存
#   8. Turbo Streams（SolidCable）でブロードキャスト
#   9. エラー時は failed! ＋ error_message ＋ ブロードキャスト
#
# parameter_values は実行時の生入力（ホワイトリスト済み）。SQL への文字列連結は
# 一切行わず、BigQuery ネイティブパラメータ（@name）としてバインドする。
class QueryExecutionJob < ApplicationJob
  queue_as :query_execution

  def perform(execution, parameter_values = {})
    execution.update!(status: :running, started_at: Time.current)

    data = run_bigquery(execution, parameter_values || {})
    schema = extract_schema(data)
    rows = extract_rows(data, schema)

    write_csv(execution, schema, rows)
    store_truncated_result(execution, schema, rows)

    execution.update!(status: :succeeded, finished_at: Time.current)
  rescue StandardError => e
    execution.update!(status: :failed, error_message: e.message, finished_at: Time.current)
  ensure
    self.class.broadcast_result(execution)
  end

  # Turbo Streams（SolidCable）へ結果/エラーを差し込む。クラスメソッドにして
  # ジョブ spec ではここをスタブし、ブロードキャスト spec で実体を検証する。
  # query_result の置換に加え、履歴一覧の先頭へ新規行を prepend する（トピック17）。
  def self.broadcast_result(execution)
    query = execution.query

    partial, locals =
      if execution.failed?
        [ "query_executions/error", { execution: execution } ]
      else
        [ "query_executions/result", { execution: execution } ]
      end

    Turbo::StreamsChannel.broadcast_replace_to(
      query,
      target: "query_result",
      partial: partial,
      locals: locals
    )

    # 履歴一覧（#query_history_rows）の先頭へ完了した実行の行を追記する。
    Turbo::StreamsChannel.broadcast_prepend_to(
      query,
      target: "query_history_rows",
      partial: "query_executions/history_row",
      locals: { execution: execution, query: query, latest_succeeded_id: query.latest_succeeded_execution&.id }
    )
  end

  private

  def run_bigquery(execution, parameter_values)
    connection = execution.query.bigquery_connection
    sql = execution.query.bound_sql
    params = bigquery_params(execution.query, parameter_values)

    job = connection.bigquery.query_job(sql, params: params, **connection.job_options)
    job.wait_until_done!
    raise(job_error_message(job)) if job.failed?

    job.data
  end

  # 定義済みパラメータ名のみホワイトリストし、各 QueryParameter のネイティブ値に
  # 変換する。date_range は Hash（@name_start / @name_end）に展開されるためマージ。
  def bigquery_params(query, raw)
    permitted = query.permit_parameter_values(raw)
    query.query_parameters.each_with_object({}) do |param, acc|
      value = param.to_bigquery_param(permitted[param.name])
      if value.is_a?(Hash)
        acc.merge!(value)
      else
        acc[param.name] = value
      end
    end
  end

  def job_error_message(job)
    err = job.error
    msg = err.is_a?(Hash) ? (err["message"] || err[:message]) : err
    "BigQuery job failed: #{msg}"
  end

  # data.fields から [{ "name" =>, "type" => }] の配列を組み立てる。
  def extract_schema(data)
    data.fields.map { |f| { "name" => f.name, "type" => f.type.to_s } }
  end

  # data の各行（Hash）を schema のカラム順に並べた配列に変換する。
  def extract_rows(data, schema)
    keys = schema.map { |c| c["name"].to_sym }
    data.map { |row| keys.map { |k| row[k] } }
  end

  # 全件 CSV を gzip でファイルに書き出す。最新1件のみ保持（既存は上書き）。
  def write_csv(execution, schema, rows)
    dir = ENV.fetch("BEAMS_CSV_PATH") { Rails.root.join("storage/csv").to_s }
    FileUtils.mkdir_p(dir)
    path = File.join(dir, "#{execution.id}.csv.gz")

    Zlib::GzipWriter.open(path) do |gz|
      gz.write(CSV.generate_line(schema.map { |c| c["name"] }))
      rows.each { |row| gz.write(CSV.generate_line(row)) }
    end
  end

  # 二重上限で切り詰めて表示用 blob を保存する。
  def store_truncated_result(execution, schema, rows)
    truncated = QueryResult.new(schema: schema, rows: rows).truncate
    execution.store_result(truncated[:schema], truncated[:rows])
    execution.result_row_count = rows.size
    execution.result_truncated = truncated[:truncated]
  end
end
