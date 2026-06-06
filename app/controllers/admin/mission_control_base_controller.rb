module Admin
  # mission_control-jobs（/jobs 配下）用の基底コントローラ。
  # config/initializers/mission_control_jobs.rb で base_controller_class に差し込む。
  #
  # 認可は ApplicationController#require_admin と同じ意図だが、MissionControl::Jobs::ApplicationController
  # の default_url_options が `server_id` を付ける都合で `redirect_to new_session_path` がメインアプリの
  # ルートを引けない。そのため明示的に main_app の URL ヘルパーを叩く。
  class MissionControlBaseController < ApplicationController
    before_action :require_admin_for_mission_control

    private

    def require_admin_for_mission_control
      if current_user.nil?
        redirect_to main_app.new_session_path, alert: "ログインしてください。"
      elsif !current_user.admin?
        redirect_to main_app.root_path, alert: "この操作には管理者権限が必要です。"
      end
    end
  end
end
