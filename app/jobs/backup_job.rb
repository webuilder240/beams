# frozen_string_literal: true

require "beams/backup"

# Creates a single SQLite backup generation. Intended to be enqueued on a
# schedule via config/recurring.yml (SolidQueue) so backups run without any
# external cron dependency.
class BackupJob < ApplicationJob
  queue_as :default

  def perform
    result = Beams::Backup.new.run
    Rails.logger.info("[BackupJob] backup created: #{result[:dir]}")
    result
  end
end
