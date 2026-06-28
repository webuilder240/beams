# frozen_string_literal: true

require "test_helper"

# トピック23: Bugsnag による例外通知の設定検証。
# - 開発・テスト環境では実際の HTTP 通知が走らない（enabled_release_stages = %w[production]）。
# - API キーは ENV["BUGSNAG_API_KEY"] から取得する（未設定なら nil で起動が落ちない）。
# - on_error コールバックで Current.user の id/email がイベントの user に付与される。
class BugsnagTest < ActiveSupport::TestCase
  def configuration
    Bugsnag.configuration
  end

  # --- release stage ---
  test "Rails.env を release_stage に設定する" do
    assert_equal Rails.env, configuration.release_stage
  end

  test "通知対象は production のみ" do
    assert_equal %w[production], configuration.enabled_release_stages
  end

  test "test 環境では should_notify_release_stage? が false（実通信なし）" do
    assert_equal false, configuration.should_notify_release_stage?
  end

  # --- env safety ---
  test "send_environment は false（センシティブな ENV 流出防止）" do
    assert_equal false, configuration.send_environment
  end

  test "BUGSNAG_API_KEY 未設定でも Bugsnag.notify が例外を投げない" do
    # test 環境では enabled_release_stages により early return される。
    assert_nothing_raised { Bugsnag.notify(StandardError.new("test")) }
  end

  # --- on_error callback (user assignment) ---
  # initializer で登録された on_error コールバックは configuration.middleware に
  # 積まれている。直接 middleware を走らせて report に副作用が乗ることを検証する
  # （test 環境では Bugsnag.notify は early return するため、blockは呼ばれない）。
  def run_middleware(exception)
    report = Bugsnag::Report.new(exception, configuration)
    configuration.middleware.run(report)
    report
  end

  test "Current.user がセットされていれば user.id と user.email が付与される" do
    user = create_user
    Current.user = user

    report = run_middleware(StandardError.new("boom"))

    assert_equal user.id, report.user[:id]
    assert_equal user.email, report.user[:email]
  ensure
    Current.reset
  end

  test "Current.user が nil でも例外を発生させずユーザー情報が空のまま" do
    Current.user = nil

    report = nil
    assert_nothing_raised { report = run_middleware(StandardError.new("boom")) }

    assert_nil report.user[:id]
    assert_nil report.user[:email]
  ensure
    Current.reset
  end
end
