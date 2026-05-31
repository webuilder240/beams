# frozen_string_literal: true

require "rails_helper"
require "sqlite3"
require "zlib"
require "json"
require "beams/backup"

RSpec.describe Beams::Backup do
  around do |example|
    Dir.mktmpdir("beams-backup-spec") do |dir|
      @tmp = Pathname.new(dir)
      example.run
    end
  end

  # Create a SQLite database file with a single table and the given rows.
  def seed_db(path, rows:)
    SQLite3::Database.new(path.to_s) do |db|
      db.execute("CREATE TABLE items (id INTEGER PRIMARY KEY, name TEXT)")
      rows.times { |i| db.execute("INSERT INTO items (name) VALUES (?)", [ "item-#{i}" ]) }
    end
  end

  # Open a (possibly gzip-compressed) sqlite file and count the rows in `items`.
  def count_items(sqlite_path)
    db = SQLite3::Database.new(sqlite_path.to_s)
    db.execute("SELECT COUNT(*) FROM items").first.first
  ensure
    db&.close
  end

  def gunzip(gz_path, dest_path)
    Zlib::GzipReader.open(gz_path.to_s) do |gz|
      File.binwrite(dest_path.to_s, gz.read)
    end
  end

  describe "#run" do
    it "creates a timestamped backup directory containing a gzip snapshot" do
      source = @tmp.join("production.sqlite3")
      seed_db(source, rows: 5)

      backup = described_class.new(
        sources: { "production" => source.to_s },
        backup_dir: @tmp.join("backups").to_s,
        generations: 7,
        now: Time.utc(2026, 5, 31, 9, 0, 0)
      )
      result = backup.run

      generation_dir = @tmp.join("backups", "20260531T090000Z")
      expect(generation_dir).to be_directory
      expect(generation_dir.join("production.sqlite3.gz")).to be_file
      expect(result[:dir]).to eq(generation_dir.to_s)
    end

    it "produces a snapshot whose data matches the source" do
      source = @tmp.join("production.sqlite3")
      seed_db(source, rows: 12)

      backup = described_class.new(
        sources: { "production" => source.to_s },
        backup_dir: @tmp.join("backups").to_s
      )
      result = backup.run

      gz = Pathname.new(result[:dir]).join("production.sqlite3.gz")
      restored = @tmp.join("restored.sqlite3")
      gunzip(gz, restored)

      expect(count_items(restored)).to eq(12)
    end

    it "captures data even while the source has uncheckpointed WAL writes" do
      source = @tmp.join("production.sqlite3")
      seed_db(source, rows: 3)

      # Keep an open connection in WAL mode with extra rows not yet checkpointed.
      writer = SQLite3::Database.new(source.to_s)
      writer.execute("PRAGMA journal_mode=WAL")
      writer.execute("INSERT INTO items (name) VALUES (?)", [ "wal-row" ])

      begin
        backup = described_class.new(
          sources: { "production" => source.to_s },
          backup_dir: @tmp.join("backups").to_s
        )
        result = backup.run

        gz = Pathname.new(result[:dir]).join("production.sqlite3.gz")
        restored = @tmp.join("restored.sqlite3")
        gunzip(gz, restored)

        expect(count_items(restored)).to eq(4)
      ensure
        writer.close
      end
    end

    it "records a manifest with integrity check results" do
      source = @tmp.join("production.sqlite3")
      seed_db(source, rows: 2)

      backup = described_class.new(
        sources: { "production" => source.to_s },
        backup_dir: @tmp.join("backups").to_s,
        now: Time.utc(2026, 5, 31, 9, 0, 0)
      )
      result = backup.run

      manifest_path = Pathname.new(result[:dir]).join("manifest.json")
      expect(manifest_path).to be_file

      manifest = JSON.parse(manifest_path.read)
      expect(manifest["timestamp"]).to eq("20260531T090000Z")
      entry = manifest["databases"].find { |d| d["name"] == "production" }
      expect(entry["integrity"]).to eq("ok")
      expect(entry["bytes"]).to be > 0
    end

    it "skips sources whose files do not exist" do
      source = @tmp.join("production.sqlite3")
      seed_db(source, rows: 1)

      backup = described_class.new(
        sources: {
          "production" => source.to_s,
          "cache" => @tmp.join("missing.sqlite3").to_s
        },
        backup_dir: @tmp.join("backups").to_s
      )
      result = backup.run

      names = result[:databases].map { |d| d[:name] }
      expect(names).to contain_exactly("production")
      expect(Pathname.new(result[:dir]).join("cache.sqlite3.gz")).not_to exist
    end
  end

  describe "generation rotation" do
    it "keeps only the configured number of newest generations" do
      source = @tmp.join("production.sqlite3")
      seed_db(source, rows: 1)
      backup_dir = @tmp.join("backups")

      times = [
        Time.utc(2026, 5, 25, 1, 0, 0),
        Time.utc(2026, 5, 26, 1, 0, 0),
        Time.utc(2026, 5, 27, 1, 0, 0),
        Time.utc(2026, 5, 28, 1, 0, 0)
      ]
      times.each do |t|
        described_class.new(
          sources: { "production" => source.to_s },
          backup_dir: backup_dir.to_s,
          generations: 3,
          now: t
        ).run
      end

      remaining = backup_dir.children.select(&:directory?).map(&:basename).map(&:to_s).sort
      expect(remaining).to eq(%w[20260526T010000Z 20260527T010000Z 20260528T010000Z])
    end
  end

  describe ".list" do
    it "returns existing generation timestamps newest first" do
      source = @tmp.join("production.sqlite3")
      seed_db(source, rows: 1)
      backup_dir = @tmp.join("backups")

      [ Time.utc(2026, 5, 25), Time.utc(2026, 5, 26) ].each do |t|
        described_class.new(
          sources: { "production" => source.to_s },
          backup_dir: backup_dir.to_s,
          now: t
        ).run
      end

      expect(described_class.list(backup_dir: backup_dir.to_s))
        .to eq(%w[20260526T000000Z 20260525T000000Z])
    end

    it "returns an empty array when the backup dir is absent" do
      expect(described_class.list(backup_dir: @tmp.join("nope").to_s)).to eq([])
    end
  end

  describe "configuration via environment" do
    it "reads backup_dir and generations from ENV by default" do
      allow(ENV).to receive(:fetch).and_call_original
      allow(ENV).to receive(:fetch).with("BEAMS_BACKUP_DIR", anything).and_return(@tmp.join("env-backups").to_s)
      allow(ENV).to receive(:fetch).with("BEAMS_BACKUP_GENERATIONS", anything).and_return("4")

      backup = described_class.new(sources: { "production" => @tmp.join("x.sqlite3").to_s })

      expect(backup.backup_dir).to eq(@tmp.join("env-backups").to_s)
      expect(backup.generations).to eq(4)
    end
  end
end
