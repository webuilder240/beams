# frozen_string_literal: true

require "test_helper"

# トピック23 (B3): ActiveJob / Solid Queue で発生した例外も Bugsnag に拾われること。
# Bugsnag gem の Railtie が ActiveJob::Base に `Bugsnag::Rails::ActiveJob` を
# include しており、`around_perform` で例外を `Bugsnag.notify` に流す。
class BugsnagIntegrationTest < ActiveJob::TestCase
  test "ActiveJob::Base に Bugsnag::Rails::ActiveJob が include されている" do
    assert_includes ActiveJob::Base.included_modules, Bugsnag::Rails::ActiveJob
  end

  # --- with a failing job ---

  # 例外を発生させるだけの最小ジョブ。テスト中に定義する。
  def failing_job_class
    Class.new(ApplicationJob) do
      def self.name = "FailingTestJob"
      def perform = raise StandardError, "boom in job"
    end
  end

  test "perform_now で raise したときに Bugsnag.notify が呼ばれる" do
    notified = []
    original = Bugsnag.method(:notify)
    Bugsnag.define_singleton_method(:notify) do |*args, **kwargs, &blk|
      notified << args
      original.call(*args, **kwargs, &blk)
    end

    begin
      error = assert_raises(StandardError) do
        failing_job_class.perform_now
      end
      assert_equal "boom in job", error.message
      assert notified.any? { |args| args.first.is_a?(StandardError) },
        "expected Bugsnag.notify to be called with a StandardError"
    ensure
      Bugsnag.singleton_class.remove_method(:notify)
      Bugsnag.define_singleton_method(:notify, original)
    end
  end
end
