# frozen_string_literal: true

require "rails_helper"

# トピック15: バックアップの自動実行。`config/recurring.yml` の production に
# 日次 BackupJob が登録されていることを検証する（外部 cron に依存しない）。
RSpec.describe "config/recurring.yml" do
  let(:config) { YAML.load_file(Rails.root.join("config/recurring.yml")) }

  it "registers a daily BackupJob under production" do
    production = config.fetch("production")
    backup_entries = production.values.select { |entry| entry["class"] == "BackupJob" }

    expect(backup_entries).not_to be_empty
  end

  it "schedules the backup on a daily cadence" do
    production = config.fetch("production")
    backup = production.values.find { |entry| entry["class"] == "BackupJob" }

    expect(backup["schedule"]).to match(/every day/i)
  end
end
