# 可視化（トピック11）。GET /queries/:query_id/visualization（設定フォーム＋結果表示）、
# PATCH /queries/:query_id/visualization（設定 upsert）。owner-scoped。
# 1クエリ1可視化（has_one）のため update は upsert（既存があれば更新、無ければ build）。
class VisualizationsController < ApplicationController
  before_action :require_login
  before_action :set_query
  before_action :set_visualization

  def show
  end

  def update
    if @visualization.update(visualization_params)
      respond_to do |format|
        format.turbo_stream
        format.html { redirect_to query_visualization_path(@query), status: :see_other }
      end
    else
      render :show, status: :unprocessable_content
    end
  end

  private

  # 所有者スコープ: current_user のクエリのみ（他人の id は 404）。
  def set_query
    @query = current_user.queries.find(params[:query_id])
  end

  # has_one の upsert: 既存可視化があればそれを、無ければデフォルト値で build する。
  def set_visualization
    @visualization = @query.visualization || @query.build_visualization
  end

  def visualization_params
    permitted = params.require(:visualization).permit(
      :chart_type, :x_column, :series_column, :display_mode,
      :counter_column, :counter_aggregation, y_columns: []
    )
    # multiple select は空文字（Rails の hidden フィールド）を含むため除去する。
    if params[:visualization].key?(:y_columns)
      permitted[:y_columns] = Array(permitted[:y_columns]).compact_blank
    else
      # y_columns 未送信のときはキーを残さない（既存値を消さない）。
      permitted.delete(:y_columns)
    end
    permitted
  end
end
