# frozen_string_literal: true

require "rails_helper"

# トピック23: Bugsnag による例外通知の設定検証。
# - 開発・テスト環境では実際の HTTP 通知が走らない（enabled_release_stages = %w[production]）。
# - API キーは ENV["BUGSNAG_API_KEY"] から取得する（未設定なら nil で起動が落ちない）。
# - on_error コールバックで Current.user の id/email がイベントの user に付与される。
RSpec.describe "Bugsnag initializer" do
  let(:configuration) { Bugsnag.configuration }

  describe "release stage" do
    it "Rails.env を release_stage に設定する" do
      expect(configuration.release_stage).to eq(Rails.env)
    end

    it "通知対象は production のみ" do
      expect(configuration.enabled_release_stages).to eq(%w[production])
    end

    it "test 環境では should_notify_release_stage? が false（実通信なし）" do
      expect(configuration.should_notify_release_stage?).to be(false)
    end
  end

  describe "env safety" do
    it "send_environment は false（センシティブな ENV 流出防止）" do
      expect(configuration.send_environment).to be(false)
    end

    it "BUGSNAG_API_KEY 未設定でも Bugsnag.notify が例外を投げない" do
      # test 環境では enabled_release_stages により early return される。
      expect { Bugsnag.notify(StandardError.new("test")) }.not_to raise_error
    end
  end

  describe "on_error callback (user assignment)" do
    after { Current.reset }

    # initializer で登録された on_error コールバックは configuration.middleware に
    # 積まれている。直接 middleware を走らせて report に副作用が乗ることを検証する
    # （test 環境では Bugsnag.notify は early return するため、blockは呼ばれない）。
    def run_middleware(exception)
      report = Bugsnag::Report.new(exception, configuration)
      configuration.middleware.run(report)
      report
    end

    it "Current.user がセットされていれば user.id と user.email が付与される" do
      user = create(:user)
      Current.user = user

      report = run_middleware(StandardError.new("boom"))

      expect(report.user[:id]).to eq(user.id)
      expect(report.user[:email]).to eq(user.email)
    end

    it "Current.user が nil でも例外を発生させずユーザー情報が空のまま" do
      Current.user = nil

      report = nil
      expect { report = run_middleware(StandardError.new("boom")) }.not_to raise_error

      expect(report.user[:id]).to be_nil
      expect(report.user[:email]).to be_nil
    end
  end
end
