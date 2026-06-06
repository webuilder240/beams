# frozen_string_literal: true

require "rails_helper"

# トピック26 グループ C: 自動バックアップは ONCE プラットフォーム
# （basecamp/once）の /hooks/pre-backup に一本化したため、
# `config/recurring.yml` からは BackupJob の定期 enqueue を撤去している。
# 手動緊急時用の `rake beams:backup` / `bin/beams-backup` は引き続き残す方針。
RSpec.describe "config/recurring.yml" do
  let(:config) { YAML.load_file(Rails.root.join("config/recurring.yml")) }

  it "does not register BackupJob under production (handled by ONCE /hooks/pre-backup)" do
    production = config.fetch("production")
    backup_entries = production.values.select { |entry| entry.is_a?(Hash) && entry["class"] == "BackupJob" }

    expect(backup_entries).to be_empty
  end

  it "still parses as a YAML hash with a production section" do
    expect(config).to be_a(Hash)
    expect(config["production"]).to be_a(Hash)
  end
end
