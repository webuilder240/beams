# mission_control-jobs（/jobs）の認可・認証設定。
#
# - 1.0 系から有効化された HTTP Basic 認証は無効化する。代わりに
#   Admin::MissionControlBaseController（require_admin 済み）を base controller として差し込み、
#   既存のセッション認証（admin ロール）でガードする。

Rails.application.config.after_initialize do
  MissionControl::Jobs.base_controller_class = "Admin::MissionControlBaseController"
  MissionControl::Jobs.http_basic_auth_enabled = false
end
