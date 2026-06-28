# frozen_string_literal: true

require "test_helper"

class BackupJobTest < ActiveJob::TestCase
  test "runs a single backup generation via Beams::Backup" do
    run_called = 0
    backup_double = Object.new
    backup_double.define_singleton_method(:run) do
      run_called += 1
      { dir: "/tmp/x", timestamp: "20260531T090000Z", databases: [] }
    end

    Beams::Backup.stub(:new, backup_double) do
      BackupJob.perform_now
    end

    assert_equal 1, run_called
  end
end
