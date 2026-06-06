module Admin
  class RedashSourcesController < ApplicationController
    before_action :require_admin
    before_action :set_redash_source, only: [ :edit, :update, :destroy ]

    def index
      @redash_sources = RedashSource.order(:name)
    end

    def new
      @redash_source = RedashSource.new
    end

    def create
      @redash_source = RedashSource.new(redash_source_params)

      if @redash_source.save
        redirect_to admin_redash_sources_path, notice: "Redash 接続を作成しました。"
      else
        render :new, status: :unprocessable_content
      end
    end

    def edit
    end

    def update
      if @redash_source.update(redash_source_update_params)
        redirect_to admin_redash_sources_path, notice: "Redash 接続を更新しました。"
      else
        render :edit, status: :unprocessable_content
      end
    end

    def destroy
      @redash_source.destroy
      redirect_to admin_redash_sources_path, notice: "Redash 接続を削除しました。"
    end

    private

    def set_redash_source
      @redash_source = RedashSource.find(params[:id])
    end

    def redash_source_params
      params.expect(redash_source: [ :name, :url, :api_key ])
    end

    # 編集時に API キーが空欄なら既存値を保持する（暗号化済み平文を再表示しない運用）。
    # `Bigquery::Connection` の SA JSON と同じパターン。
    def redash_source_update_params
      permitted = redash_source_params
      permitted.delete(:api_key) if permitted[:api_key].blank?
      permitted
    end
  end
end
