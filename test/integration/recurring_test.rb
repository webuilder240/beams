# frozen_string_literal: true

require "test_helper"

# トピック26 グループ C: 自動バックアップは ONCE プラットフォーム
# （basecamp/once）の /hooks/pre-backup に一本化したため、
# `config/recurring.yml` からは BackupJob の定期 enqueue を撤去している。
# 手動緊急時用の `rake beams:backup` / `bin/beams-backup` は引き続き残す方針。
class RecurringTest < ActiveSupport::TestCase
  def config
    YAML.load_file(Rails.root.join("config/recurring.yml"))
  end

  test "does not register BackupJob under production (handled by ONCE /hooks/pre-backup)" do
    production = config.fetch("production")
    backup_entries = production.values.select { |entry| entry.is_a?(Hash) && entry["class"] == "BackupJob" }

    assert_empty backup_entries
  end

  test "still parses as a YAML hash with a production section" do
    assert_kind_of Hash, config
    assert_kind_of Hash, config["production"]
  end
end
