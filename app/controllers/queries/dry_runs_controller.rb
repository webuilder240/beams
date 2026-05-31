module Queries
  # dry-run（コスト保護★）エンドポイント。
  # POST /queries/:query_id/dry_run。SQL 本文はリクエストボディの現在の
  # エディタ内容を受け取り、接続コンテキストは所有クエリの bigquery_connection から得る。
  # `DryRun`（課金ゼロ）＋ `CostEstimate`（GB/円換算）＋ `over_limit?`（上限判定）で
  # JSON `{ gb, yen, over_limit, limit_gb, error }` を返す。
  class DryRunsController < ApplicationController
    before_action :require_login
    before_action :set_query

    def create
      bytes = DryRun.new(connection, dry_run_sql).call[:bytes_processed]
      estimate = CostEstimate.new(bytes: bytes, yen_per_tb: yen_per_tb).estimate

      render json: success_payload(estimate, bytes)
    rescue Google::Cloud::Error => e
      render json: error_payload(e.message), status: :unprocessable_content
    end

    private

    # 所有者スコープ: current_user のクエリのみ（他人の id は 404）。
    def set_query
      @query = current_user.queries.find(params[:query_id])
    end

    def connection
      @query.bigquery_connection
    end

    # 保存済み SQL ではなく、ライブ編集中の SQL 本文を使う（未指定なら保存済みにフォールバック）。
    def dry_run_sql
      params[:sql].presence || @query.sql_body
    end

    def yen_per_tb
      ApplicationSetting.instance.bigquery_yen_per_tb
    end

    def success_payload(estimate, bytes)
      over = connection.over_limit?(bytes)

      {
        gb: estimate[:gb],
        yen: estimate[:yen],
        over_limit: over,
        limit_gb: limit_gb,
        error: over ? limit_message(estimate) : nil
      }
    end

    def error_payload(message)
      { gb: nil, yen: nil, over_limit: false, limit_gb: limit_gb, error: message }
    end

    def limit_gb
      max = connection.maximum_bytes_billed
      max && CostEstimate.bytes_to_gb(max)
    end

    def limit_message(estimate)
      "推定 #{estimate[:gb]} GB は接続の上限 #{limit_gb} GB を超えています"
    end
  end
end
