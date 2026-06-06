# frozen_string_literal: true

require "rails_helper"

# トピック23 (B3): ActiveJob / Solid Queue で発生した例外も Bugsnag に拾われること。
# Bugsnag gem の Railtie が ActiveJob::Base に `Bugsnag::Rails::ActiveJob` を
# include しており、`around_perform` で例外を `Bugsnag.notify` に流す。
RSpec.describe "Bugsnag ActiveJob integration" do
  it "ActiveJob::Base に Bugsnag::Rails::ActiveJob が include されている" do
    expect(ActiveJob::Base.included_modules).to include(Bugsnag::Rails::ActiveJob)
  end

  context "with a failing job" do
    # 例外を発生させるだけの最小ジョブ。テスト中に定義する。
    let(:failing_job_class) do
      Class.new(ApplicationJob) do
        def self.name = "FailingTestJob"
        def perform = raise StandardError, "boom in job"
      end
    end

    it "perform_now で raise したときに Bugsnag.notify が呼ばれる" do
      allow(Bugsnag).to receive(:notify).and_call_original

      expect {
        failing_job_class.perform_now
      }.to raise_error(StandardError, "boom in job")

      expect(Bugsnag).to have_received(:notify).with(
        instance_of(StandardError), true
      )
    end
  end
end
