# ウィジェット並び順リソース（トピック19）。並び替えは D&D（SortableJS + Stimulus コントローラ +
# PATCH widget_order）。Turbo Stream で `<turbo-frame id="widgets">` 相当を再描画し、
# ページリロードなしで反映する。組織フルオープン（§4.9）のため owner-scope しない。
class WidgetOrdersController < ApplicationController
  before_action :require_login
  before_action :set_dashboard

  def update
    @dashboard.reorder_widgets!(params[:widget_ids])
    @widgets = @dashboard.ordered_widgets.includes(query: [ :visualization ])
    respond_to do |format|
      format.turbo_stream
      format.html { redirect_to dashboard_path(@dashboard) }
    end
  end

  private

  def set_dashboard
    @dashboard = Dashboard.find(params[:dashboard_id])
  end
end
