class SchemaCachesController < ApplicationController
  before_action :require_login
  before_action :set_connection

  # スキーマキャッシュを手動更新する。TTL を無視して BigQuery から再取得・上書きする。
  def refresh
    @connection&.sync_schema!(force: true)
    redirect_to schema_browser_path, notice: "スキーマを更新しました。"
  end

  private

  def set_connection
    @connection = Bigquery::Connection.order(:name).first
  end
end
