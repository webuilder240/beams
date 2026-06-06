# frozen_string_literal: true

# トピック23: Bugsnag による例外通知。
#
# - API キーは ENV["BUGSNAG_API_KEY"] から取得する（B1）。
# - 通知対象は production 環境のみ。development / test では
#   `enabled_release_stages` の制御により実通信は行われない（B2）。
# - ActiveJob / Solid Queue の例外も Bugsnag gem の Railtie によって
#   自動的に捕捉される（B3。明示的な無効化はしない）。
# - on_error コールバックでログイン中ユーザー情報（Current.user の id / email）を
#   イベントに付与する（B4）。未ログイン時は何もしない。
Bugsnag.configure do |config|
  config.api_key = ENV["BUGSNAG_API_KEY"]
  config.release_stage = Rails.env
  config.enabled_release_stages = %w[production]
  config.app_version = ENV["APP_VERSION"] if ENV["APP_VERSION"].present?
  config.send_environment = false
end

# Current.user がセットされていればイベントに user 情報を付与する。
# `on_error` コールバックは Bugsnag のミドルウェアスタックで実行される。
Bugsnag.add_on_error(lambda do |report|
  user = Current.user
  next true if user.nil?

  report.user = { id: user.id, email: user.email }
  true
end)
