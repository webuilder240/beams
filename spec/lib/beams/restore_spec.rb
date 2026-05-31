# frozen_string_literal: true

require "rails_helper"
require "sqlite3"
require "zlib"
require "json"
require "beams/backup"
require "beams/restore"

RSpec.describe Beams::Restore do
  around do |example|
    Dir.mktmpdir("beams-restore-spec") do |dir|
      @tmp = Pathname.new(dir)
      example.run
    end
  end

  def seed_db(path, rows:)
    SQLite3::Database.new(path.to_s) do |db|
      db.execute("CREATE TABLE items (id INTEGER PRIMARY KEY, name TEXT)")
      rows.times { |i| db.execute("INSERT INTO items (name) VALUES (?)", [ "item-#{i}" ]) }
    end
  end

  def count_items(path)
    db = SQLite3::Database.new(path.to_s)
    db.execute("SELECT COUNT(*) FROM items").first.first
  ensure
    db&.close
  end

  # Build a backup generation containing a snapshot of `source` and return the
  # generation timestamp.
  def make_backup(source, backup_dir, name: "production", now: Time.utc(2026, 5, 31, 9, 0, 0))
    Beams::Backup.new(
      sources: { name => source.to_s },
      backup_dir: backup_dir.to_s,
      now: now
    ).run[:timestamp]
  end

  describe "#run" do
    it "restores the database from the specified generation" do
      source = @tmp.join("source.sqlite3")
      seed_db(source, rows: 8)
      backup_dir = @tmp.join("backups")
      timestamp = make_backup(source, backup_dir)

      target = @tmp.join("production.sqlite3")
      seed_db(target, rows: 1) # stale current db

      restore = described_class.new(
        timestamp,
        targets: { "production" => target.to_s },
        backup_dir: backup_dir.to_s,
        now: Time.utc(2026, 5, 31, 10, 0, 0)
      )
      restore.run

      expect(count_items(target)).to eq(8)
    end

    it "moves the current database aside with a timestamped safety copy" do
      source = @tmp.join("source.sqlite3")
      seed_db(source, rows: 4)
      backup_dir = @tmp.join("backups")
      timestamp = make_backup(source, backup_dir)

      target = @tmp.join("production.sqlite3")
      seed_db(target, rows: 99)

      restore = described_class.new(
        timestamp,
        targets: { "production" => target.to_s },
        backup_dir: backup_dir.to_s,
        now: Time.utc(2026, 5, 31, 10, 0, 0)
      )
      result = restore.run

      safety = result[:databases].first[:safety_copy]
      expect(safety).to be_truthy
      expect(File).to exist(safety)
      expect(count_items(Pathname.new(safety))).to eq(99)
    end

    it "resolves 'latest' to the newest generation" do
      backup_dir = @tmp.join("backups")

      old_source = @tmp.join("old.sqlite3")
      seed_db(old_source, rows: 2)
      make_backup(old_source, backup_dir, now: Time.utc(2026, 5, 25))

      new_source = @tmp.join("new.sqlite3")
      seed_db(new_source, rows: 7)
      make_backup(new_source, backup_dir, now: Time.utc(2026, 5, 26))

      target = @tmp.join("production.sqlite3")
      restore = described_class.new(
        "latest",
        targets: { "production" => target.to_s },
        backup_dir: backup_dir.to_s,
        now: Time.utc(2026, 5, 27)
      )
      result = restore.run

      expect(result[:timestamp]).to eq("20260526T000000Z")
      expect(count_items(target)).to eq(7)
    end

    it "raises when the generation does not exist" do
      restore = described_class.new(
        "19990101T000000Z",
        targets: { "production" => @tmp.join("x.sqlite3").to_s },
        backup_dir: @tmp.join("backups").to_s
      )
      expect { restore.run }.to raise_error(Beams::Restore::GenerationNotFound)
    end

    it "rolls back the current database if a restore step fails" do
      source = @tmp.join("source.sqlite3")
      seed_db(source, rows: 5)
      backup_dir = @tmp.join("backups")
      timestamp = make_backup(source, backup_dir)

      target = @tmp.join("production.sqlite3")
      seed_db(target, rows: 42)

      restore = described_class.new(
        timestamp,
        targets: { "production" => target.to_s },
        backup_dir: backup_dir.to_s,
        now: Time.utc(2026, 5, 31, 10, 0, 0)
      )

      # Force the decompression step to blow up after the safety copy is taken.
      allow(restore).to receive(:decompress).and_raise(StandardError, "boom")

      expect { restore.run }.to raise_error(StandardError, /boom/)
      # original data must be intact after rollback
      expect(count_items(target)).to eq(42)
    end
  end

  describe ".available" do
    it "lists generations from the backup directory" do
      source = @tmp.join("source.sqlite3")
      seed_db(source, rows: 1)
      backup_dir = @tmp.join("backups")
      make_backup(source, backup_dir, now: Time.utc(2026, 5, 25))
      make_backup(source, backup_dir, now: Time.utc(2026, 5, 26))

      expect(described_class.available(backup_dir: backup_dir.to_s))
        .to eq(%w[20260526T000000Z 20260525T000000Z])
    end
  end
end
