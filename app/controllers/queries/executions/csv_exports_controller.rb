module Queries
  module Executions
    # 全件 CSV ダウンロード（トピック10・X-Sendfile / Thruster）。
    # GET /queries/:query_id/executions/latest/csv。最新成功 QueryExecution の
    # 全件 CSV（ジョブが実行成功時に storage/csv/<id>.csv.gz へ書き出し済み）を
    # send_file で即時配信する。BigQuery 再フェッチは行わない。表示用の先頭 N 行
    # blob とは別管理のため、result_truncated: true でも全件がダウンロードできる。
    class CsvExportsController < ApplicationController
      before_action :require_login
      before_action :set_query

      def show
        execution = @query.latest_succeeded_execution
        return head :not_found if execution.nil?

        # パスは整数の id だけから組み立てる（ユーザー入力・文字列属性を含めない）。
        # CSV 出力先は ENV "BEAMS_CSV_PATH" で上書き可能（並列テストで worker 隔離するため）。
        dir = ENV.fetch("BEAMS_CSV_PATH") { Rails.root.join("storage/csv").to_s }
        path = File.join(dir, "#{execution.id.to_i}.csv.gz")
        return head :not_found unless File.exist?(path)

        send_file path,
                  filename: download_filename,
                  type: "text/csv",
                  disposition: "attachment",
                  x_sendfile: true
      end

      private

      # 所有者スコープ: current_user のクエリのみ（他人の id は 404）。
      def set_query
        @query = current_user.queries.find(params[:query_id])
      end

      # ダウンロード時のファイル名（ヘッダー用）。ファイルシステムパスではないため
      # 安全だが、念のため英数字・ハイフン・アンダースコア以外を除去する。
      def download_filename
        base = @query.title.to_s.gsub(/[^\w\-]+/, "_")
        base = "query" if base.blank?
        "#{base}.csv.gz"
      end
    end
  end
end
