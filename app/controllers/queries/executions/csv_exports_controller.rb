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
        path = execution && csv_path(execution)

        return head :not_found if path.nil? || !File.exist?(path)

        send_file path,
                  filename: "#{@query.title}.csv.gz",
                  type: "text/csv",
                  disposition: "attachment",
                  x_sendfile: true
      end

      private

      # 所有者スコープ: current_user のクエリのみ（他人の id は 404）。
      def set_query
        @query = current_user.queries.find(params[:query_id])
      end

      def csv_path(execution)
        Rails.root.join("storage/csv/#{execution.id}.csv.gz")
      end
    end
  end
end
