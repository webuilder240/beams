# ダッシュボード CRUD（トピック12）。**閲覧・編集は全ログインユーザーに許可**
# （計画書 §4.9: 組織フルオープン）。owner-scope せず `Dashboard.find` で取得する。
# `create`/`update` で所有者として `current_user` を記録する（制限には使わない）。
class DashboardsController < ApplicationController
  before_action :require_login
  before_action :set_dashboard, only: [ :show, :edit, :update, :destroy ]

  def index
    @q = params[:q]
    @dashboards = Dashboard.title_matching(@q).order(updated_at: :desc)
  end

  def show
    @widgets = @dashboard.ordered_widgets.includes(query: [ :visualization ])
    @queries = current_user.queries.order(:title)
  end

  def new
    @dashboard = Dashboard.new
  end

  def create
    @dashboard = Dashboard.new(dashboard_params)
    @dashboard.user = current_user

    if @dashboard.save
      redirect_to dashboard_path(@dashboard), notice: "ダッシュボードを作成しました。"
    else
      render :new, status: :unprocessable_content
    end
  end

  def edit
  end

  def update
    if @dashboard.update(dashboard_params)
      redirect_to dashboard_path(@dashboard), notice: "ダッシュボードを更新しました。"
    else
      render :edit, status: :unprocessable_content
    end
  end

  def destroy
    @dashboard.destroy
    redirect_to dashboards_path, notice: "ダッシュボードを削除しました。"
  end

  private

  # 組織フルオープン（§4.9）: 全ログインユーザーが全ダッシュボードを操作可能。
  def set_dashboard
    @dashboard = Dashboard.find(params[:id])
  end

  def dashboard_params
    params.expect(dashboard: [ :title, :description ])
  end
end
