class QueriesController < ApplicationController
  before_action :require_login
  before_action :set_query, only: [ :show, :edit, :update, :destroy ]

  def index
    # 組織フルオープン（§4.9）: 全ログインユーザーが全クエリを閲覧可能。
    @queries = Query.title_matching(params[:q]).order(updated_at: :desc)
    @q = params[:q]
  end

  def show
    # 結果エリア初期表示用に直近の実行を読み込む（トピック10）。
    @latest_execution = @query.query_executions.order(created_at: :desc).first

    return if params[:query_params].blank?

    # 実行時パラメータ受け取りの設計（グループ5）。
    # 1) 定義済みパラメータ名のみにホワイトリストフィルタ（未定義の名前は無視）。
    # 2) 全パラメータ必須運用: 未入力が 1 つでもあれば実行を拒否しエラー表示。
    raw = params[:query_params].to_unsafe_h
    @permitted_parameter_values = @query.permit_parameter_values(raw)
    @missing_parameters = @query.missing_parameter_values(raw)
    @parameter_values_ready = @missing_parameters.empty?
  end

  def new
    @query = current_user.queries.new(bigquery_connection_id: default_connection_id)
    @connections = Bigquery::Connection.order(:name)
    load_schema_for(@query.bigquery_connection)
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
    load_schema_for(@query.bigquery_connection)
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

  # 組織フルオープン（§4.9）: 全ログインユーザーが全クエリを操作可能。
  # 所有者（user）は作成時に記録するが、アクセス制限には使わない。
  def set_query
    @query = Query.find(params[:id])
  end

  def query_params
    params.expect(query: [ :title, :sql_body, :bigquery_connection_id ])
  end

  # 接続が 1 件だけならデフォルト選択する（新規フォームの利便性）。
  def default_connection_id
    Bigquery::Connection.order(:name).first&.id
  end

  # エディタ脇のスキーマブラウザ用に、対象接続のキャッシュ済みスキーマを読み込む。
  # キャッシュ未取得の接続は同期せず（コスト/レイテンシ回避）、ブラウザは非表示。
  def load_schema_for(connection)
    return if connection.nil?
    return unless Rails.cache.exist?(connection.schema_cache_key)

    @schema = connection.cached_schema
  end
end
