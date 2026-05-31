class QueriesController < ApplicationController
  before_action :require_login
  before_action :set_query, only: [ :show, :edit, :update, :destroy ]

  def index
    @queries = current_user.queries.title_matching(params[:q]).order(updated_at: :desc)
    @q = params[:q]
  end

  def show
  end

  def new
    @query = current_user.queries.new(bigquery_connection_id: default_connection_id)
    @connections = Bigquery::Connection.order(:name)
  end

  def create
    @query = current_user.queries.new(query_params)

    if @query.save
      redirect_to query_path(@query), notice: "クエリを保存しました。"
    else
      @connections = Bigquery::Connection.order(:name)
      render :new, status: :unprocessable_content
    end
  end

  def edit
    @connections = Bigquery::Connection.order(:name)
  end

  def update
    if @query.update(query_params)
      redirect_to query_path(@query), notice: "クエリを更新しました。"
    else
      @connections = Bigquery::Connection.order(:name)
      render :edit, status: :unprocessable_content
    end
  end

  def destroy
    @query.destroy
    redirect_to queries_path, notice: "クエリを削除しました。"
  end

  private

  # 所有者スコープ: current_user のクエリのみ操作可能（他人の id は 404）。
  def set_query
    @query = current_user.queries.find(params[:id])
  end

  def query_params
    params.expect(query: [ :title, :sql_body, :bigquery_connection_id ])
  end

  # 接続が 1 件だけならデフォルト選択する（新規フォームの利便性）。
  def default_connection_id
    Bigquery::Connection.order(:name).first&.id
  end
end
