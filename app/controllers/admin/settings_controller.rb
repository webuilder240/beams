module Admin
  # コスト単価などアプリ全体のシングルトン設定（`ApplicationSetting`）の編集。admin 専用。
  class SettingsController < ApplicationController
    before_action :require_admin
    before_action :set_setting

    def edit
    end

    def update
      if @setting.update(setting_params)
        redirect_to edit_admin_settings_path, notice: "コスト単価を更新しました。"
      else
        render :edit, status: :unprocessable_content
      end
    end

    private

    def set_setting
      @setting = ApplicationSetting.instance
    end

    def setting_params
      params.expect(application_setting: [ :bigquery_yen_per_tb ])
    end
  end
end
