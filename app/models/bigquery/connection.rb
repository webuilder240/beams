require "json"
require "google/cloud/bigquery"

class Bigquery::Connection < ApplicationRecord
  # SA JSON 鍵は SQLite に平文で保存する。保護はホスト側のディスク暗号化・
  # `/storage` ボリュームのアクセス制御・ファイルパーミッションに委ねる
  # （トピック27 / docs/adr/0002-drop-active-record-encryption.md）。

  validates :name, presence: true
  validates :project_id,
            presence: true,
            format: { with: /\A[a-zA-Z0-9-]+\z/, message: "は英数字とハイフンのみ使用できます" }
  validates :service_account_json, presence: true
  validate :service_account_json_must_be_a_json_object
  validates :maximum_bytes_billed,
            numericality: { only_integer: true, greater_than: 0 },
            allow_nil: true

  # SA JSON 鍵とプロジェクト ID から BigQuery クライアントを生成して返す。
  # credentials にはパース済みのハッシュをそのまま渡せるため、一時ファイルは不要。
  def bigquery
    @bigquery ||= Google::Cloud::Bigquery.new(
      project_id: project_id,
      credentials: parsed_service_account
    )
  end

  # コスト上限の GB 入力 ↔ バイト保存を仲介する仮想属性。
  # フォームではバイト直打ちは非現実的なため GB で入力させ、バイト列へ換算して保存する。
  # 空欄は「上限なし（nil）」を維持する（トピック04の仕様）。換算は CostEstimate に集約。
  def maximum_bytes_billed_gb
    return nil if maximum_bytes_billed.nil?

    CostEstimate.bytes_to_gb(maximum_bytes_billed)
  end

  def maximum_bytes_billed_gb=(gb)
    self.maximum_bytes_billed = CostEstimate.gb_to_bytes(gb)
  end

  # スキャン予定バイト数が接続の上限（`maximum_bytes_billed`）を超えるか判定する。
  # 上限未設定（nil）は「上限なし」として常に false。境界（等しい）は超過扱いしない。
  def over_limit?(bytes_processed)
    return false if maximum_bytes_billed.nil?

    bytes_processed.to_i > maximum_bytes_billed
  end

  # BigQuery ジョブ生成時に渡す共通オプション。接続に上限があれば
  # `maximum_bytes_billed:` を含める（BigQuery 側でも上限を強制させるための下地）。
  # 上限なし（nil）のときは空ハッシュ。実行ジョブ（トピック10）でも本メソッドを使う。
  def job_options
    return {} if maximum_bytes_billed.nil?

    { maximum_bytes_billed: maximum_bytes_billed }
  end

  # 課金ゼロ（`dryrun: true`）でジョブを投入する。接続の `job_options`
  # （= `maximum_bytes_billed`）を併せて渡し、上限を BigQuery 側にも伝える。
  def dry_run_job(sql)
    bigquery.query_job(sql, dryrun: true, **job_options)
  end

  # BigQuery への接続を診断する。
  # (1) dry-run（`SELECT 1`）でクエリ実行権限（bigquery.jobs.create 等）を確認し、
  # (2) `datasets.list` でデータセット閲覧権限（bigquery.datasets.list）を確認する。
  # `datasets.list` 権限があればデータセットが 0 件でも成功扱いとする。
  # 成功時は `{ success: true }`、失敗時は
  # `{ success: false, missing_permissions: [...], message: "..." }` を返す。
  # 外部 API 呼び出しを伴うため、テストではクライアントをスタブする。
  def test_connection
    missing = []
    messages = []

    check_dry_run(missing, messages)
    check_datasets_list(missing, messages)

    return { success: true } if messages.empty?

    {
      success: false,
      missing_permissions: missing.uniq,
      message: messages.join(" / ")
    }
  end

  # スキーマキャッシュの TTL（ADR 0001）。
  SCHEMA_CACHE_TTL = 24.hours

  # キャッシュ済みのスキーマ構造を返す。未キャッシュ（または失効）なら sync して保存する。
  # 初回アクセス時取得と TTL を両立する（ADR 0001）。
  def cached_schema
    Rails.cache.fetch(schema_cache_key, expires_in: SCHEMA_CACHE_TTL) do
      build_schema_structure
    end
  end

  # BigQuery からスキーマ（datasets → tables → columns）を取得し、
  # ネスト構造のハッシュとして SolidCache に保存して返す。
  # force: true のときは既存キャッシュの有無に関わらず再取得・上書きする。
  # 外部 API 呼び出しを伴うため、テストではクライアントをスタブする。
  def sync_schema!(force: false)
    return cached_schema if !force && Rails.cache.exist?(schema_cache_key)

    structure = build_schema_structure
    Rails.cache.write(schema_cache_key, structure, expires_in: SCHEMA_CACHE_TTL)
    structure
  end

  # SolidCache の保存キー（接続単位）。
  def schema_cache_key
    "bigquery:schema:#{id}"
  end

  private

  # BigQuery を 3 段（datasets.list / tables.list / INFORMATION_SCHEMA.COLUMNS）で
  # 叩き、ツリー描画用のネスト構造ハッシュを組み立てる。
  def build_schema_structure
    datasets = bigquery.datasets.map do |dataset|
      columns_by_table = fetch_columns_by_table(dataset.dataset_id)

      {
        dataset_id: dataset.dataset_id,
        name: dataset.name,
        tables: dataset.tables.map do |table|
          {
            table_id: table.table_id,
            table_type: table.type,
            columns: columns_by_table.fetch(table.table_id, [])
          }
        end
      }
    end

    { fetched_at: Time.current, datasets: datasets }
  end

  # 1 データセット分の INFORMATION_SCHEMA.COLUMNS を引き、table_id ごとに
  # カラム情報の配列へまとめる。
  def fetch_columns_by_table(dataset_id)
    sql = <<~SQL.squish
      SELECT table_name, column_name, data_type, is_nullable, ordinal_position
      FROM `#{dataset_id}`.INFORMATION_SCHEMA.COLUMNS
      ORDER BY table_name, ordinal_position
    SQL

    bigquery.query(sql).each_with_object(Hash.new { |h, k| h[k] = [] }) do |row, acc|
      acc[row[:table_name]] << {
        column_name: row[:column_name],
        data_type: row[:data_type],
        is_nullable: row[:is_nullable].to_s.upcase == "YES",
        ordinal_position: row[:ordinal_position]
      }
    end
  end

  def check_dry_run(missing, messages)
    bigquery.query_job("SELECT 1", dryrun: true)
  rescue Google::Cloud::Error => e
    record_failure(e, missing, messages)
  end

  def check_datasets_list(missing, messages)
    bigquery.datasets
  rescue Google::Cloud::Error => e
    record_failure(e, missing, messages)
  end

  def record_failure(error, missing, messages)
    missing.concat(extract_missing_permissions(error.message))
    messages << error.message
  end

  # BigQuery のエラーメッセージから `bigquery.xxx.yyy` 形式の権限名を抽出する。
  def extract_missing_permissions(message)
    message.to_s.scan(/\b(bigquery\.[a-zA-Z]+\.[a-zA-Z]+)\b/).flatten.uniq
  end

  def parsed_service_account
    JSON.parse(service_account_json)
  end

  def service_account_json_must_be_a_json_object
    return if service_account_json.blank?

    parsed = JSON.parse(service_account_json)
    errors.add(:service_account_json, "はJSONオブジェクトである必要があります") unless parsed.is_a?(Hash)
  rescue JSON::ParserError
    errors.add(:service_account_json, "は正しいJSON形式である必要があります")
  end
end
