module Queries
  # 非同期実行エンドポイント（トピック10）。
  # POST /queries/:query_id/executions。所有クエリのみ（他人の id は 404）。
  # 全パラメータ必須運用: 未入力が 1 つでもあれば実行せずエラー表示。
  # 同時実行 20 件上限を超える場合は pending のまま作成しジョブを待機させる。
  class ExecutionsController < ApplicationController
    before_action :require_login
    before_action :set_query

    CONCURRENCY_LIMIT = 20

    def create
      raw = parameter_values
      missing = @query.missing_parameter_values(raw)

      if missing.any?
        return render_missing(missing)
      end

      execution = @query.query_executions.create!(status: initial_status)
      QueryExecutionJob.perform_later(execution, @query.permit_parameter_values(raw))

      respond_to do |format|
        format.turbo_stream { render_running(execution) }
        format.html { redirect_to query_path(@query), status: :see_other }
      end
    end

    private

    # 所有者スコープ: current_user のクエリのみ（他人の id は 404）。
    def set_query
      @query = current_user.queries.find(params[:query_id])
    end

    def parameter_values
      params[:query_params]&.to_unsafe_h || {}
    end

    # 同時実行（running/pending）が上限以上なら pending で待機、そうでなければ running。
    def initial_status
      active = QueryExecution.where(status: [ :running, :pending ]).count
      active >= CONCURRENCY_LIMIT ? :pending : :running
    end

    def render_missing(missing)
      message = "未入力のパラメータがあります: #{missing.join(', ')}"
      respond_to do |format|
        format.turbo_stream do
          render turbo_stream: turbo_stream.replace(
            "query_result",
            partial: "query_executions/error",
            locals: { message: message }
          ), status: :unprocessable_content
        end
        format.html do
          render partial: "query_executions/error",
                 locals: { message: message },
                 status: :unprocessable_content
        end
      end
    end

    def render_running(execution)
      render turbo_stream: turbo_stream.replace(
        "query_result",
        partial: "query_executions/running",
        locals: { execution: execution }
      ), status: :accepted
    end
  end
end
