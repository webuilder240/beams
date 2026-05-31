module Queries
  # 非同期実行エンドポイント（トピック10）。
  # POST /queries/:query_id/executions。実行（書き込み/課金）は所有クエリのみ（他人の id は 404）。
  # 全パラメータ必須運用: 未入力が 1 つでもあれば実行せずエラー表示。
  # 同時実行 20 件上限を超える場合は pending のまま作成しジョブを待機させる。
  #
  # GET /queries/:query_id/executions/:id（過去結果の再表示・読み取り）は
  # トピック13（組織フルオープン §4.9）に合わせ全ユーザー可。実行（create）のみ
  # 所有者スコープ（書き込み/課金は所有者だけ）に制限する。
  class ExecutionsController < ApplicationController
    before_action :require_login
    before_action :set_query, only: [ :create ]
    before_action :set_query_full_open, only: [ :show ]

    CONCURRENCY_LIMIT = 20

    # 過去実行の結果テーブル再表示（トピック17・フルオープン）。クエリ自体は全件
    # 閲覧可（Query.find）。当該クエリ配下に存在しない execution id は
    # @query.query_executions.find が RecordNotFound → 404。存在しない query_id も 404。
    # 状態に応じて _state（成功＝_result / 失敗＝_error / 実行中＝_running）で描画。
    def show
      execution = @query.query_executions.find(params[:id])

      respond_to do |format|
        format.turbo_stream do
          render turbo_stream: turbo_stream.replace(
            "query_result",
            partial: "query_executions/state",
            locals: { execution: execution }
          )
        end
        format.html do
          render partial: "query_executions/state", locals: { execution: execution }
        end
      end
    end

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

    # 実行（create）用の所有者スコープ: current_user のクエリのみ（他人の id は 404）。
    # 書き込み/課金を伴うため所有者に限定する。
    def set_query
      @query = current_user.queries.find(params[:query_id])
    end

    # 過去結果の再表示（show）用フルオープンスコープ（トピック13 §4.9）:
    # 全ログインユーザーが全クエリの過去結果を再表示できる。存在しない id は 404。
    def set_query_full_open
      @query = Query.find(params[:query_id])
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
