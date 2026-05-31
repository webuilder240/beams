class SchemaBrowsersController < ApplicationController
  before_action :require_login
  before_action :set_connection
  # 初回アクセス時取得 + TTL を両立（キャッシュ未設定なら sync が走る）。
  before_action :load_schema

  def show
  end

  private

  def set_connection
    @connection = Bigquery::Connection.order(:name).first
    redirect_to bigquery_connections_path, alert: "BigQuery 接続を先に作成してください。" if @connection.nil?
  end

  def load_schema
    return if @connection.nil?

    @schema = @connection.cached_schema
  end
end
