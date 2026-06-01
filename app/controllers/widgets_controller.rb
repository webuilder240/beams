# ウィジェットの追加・削除（トピック12）。各アクションは Turbo Stream で
# `<turbo-frame id="widgets">` 相当を再描画し、ページリロードなしで反映する。
# 並べ替えは WidgetOrdersController（トピック19）を参照。
# 組織フルオープン（§4.9）のため owner-scope しない。
class WidgetsController < ApplicationController
  before_action :require_login
  before_action :set_dashboard
  before_action :set_widget, only: [ :destroy ]

  def create
    @widget = @dashboard.widgets.new(widget_params)
    @widget.position = next_position

    if @widget.save
      respond_with_widgets(notice: "ウィジェットを追加しました。")
    else
      redirect_to dashboard_path(@dashboard), alert: "ウィジェットを追加できませんでした。"
    end
  end

  def destroy
    @widget.destroy
    respond_with_widgets(notice: "ウィジェットを削除しました。")
  end

  private

  def set_dashboard
    @dashboard = Dashboard.find(params[:dashboard_id])
  end

  def set_widget
    @widget = @dashboard.widgets.find(params[:id])
  end

  def widget_params
    params.expect(widget: [ :query_id, :column_span, :title_override ])
  end

  # 末尾に追加するための新しい position（現在の最大 + 1）。空なら 0。
  def next_position
    max = @dashboard.widgets.maximum(:position)
    max.nil? ? 0 : max + 1
  end

  # ウィジェット一覧（Turbo Frame）を再描画する。HTML フォールバックは詳細へ戻る。
  def respond_with_widgets(notice: nil)
    @widgets = @dashboard.ordered_widgets.includes(query: [ :visualization ])
    respond_to do |format|
      format.turbo_stream
      format.html { redirect_to dashboard_path(@dashboard), notice: notice }
    end
  end
end
