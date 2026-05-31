module Bigquery
  class ConnectionsController < ApplicationController
    before_action :require_admin
    before_action :set_connection, only: [ :edit, :update, :destroy ]

    def index
      @connections = Bigquery::Connection.order(:name)
    end

    def new
      @connection = Bigquery::Connection.new
    end

    def create
      @connection = Bigquery::Connection.new(connection_params)

      if @connection.save
        redirect_to bigquery_connections_path, notice: "接続を作成しました。"
      else
        render :new, status: :unprocessable_content
      end
    end

    def edit
    end

    def update
      if @connection.update(connection_update_params)
        redirect_to bigquery_connections_path, notice: "接続を更新しました。"
      else
        render :edit, status: :unprocessable_content
      end
    end

    def destroy
      @connection.destroy
      redirect_to bigquery_connections_path, notice: "接続を削除しました。"
    end

    private

    def set_connection
      @connection = Bigquery::Connection.find(params[:id])
    end

    def connection_params
      params.expect(bigquery_connection: [ :name, :project_id, :service_account_json, :maximum_bytes_billed ])
    end

    # 編集時に SA JSON が空欄なら既存値を保持する（セキュリティ: 平文を再表示しないため、
    # 「変更する場合のみ入力」運用）。空欄のキーは update から除外する。
    def connection_update_params
      permitted = connection_params
      permitted.delete(:service_account_json) if permitted[:service_account_json].blank?
      permitted
    end
  end
end
