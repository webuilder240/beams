# frozen_string_literal: true

require "rails_helper"
require "sqlite3"
require "beams/once/pre_backup"

RSpec.describe Beams::Once::PreBackup do
  around do |example|
    Dir.mktmpdir("beams-once-pre-backup-spec") do |dir|
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

  def count_items(sqlite_path)
    db = SQLite3::Database.new(sqlite_path.to_s)
    db.execute("SELECT COUNT(*) FROM items").first.first
  ensure
    db&.close
  end

  describe "#run" do
    it "writes a consistent snapshot of every source database to the destination" do
      sources = {
        "production" => @tmp.join("production.sqlite3"),
        "cache" => @tmp.join("cache.sqlite3"),
        "queue" => @tmp.join("queue.sqlite3"),
        "cable" => @tmp.join("cable.sqlite3")
      }
      seed_db(sources["production"], rows: 5)
      seed_db(sources["cache"], rows: 2)
      seed_db(sources["queue"], rows: 3)
      seed_db(sources["cable"], rows: 1)

      destination = @tmp.join("once-pending")
      result = described_class.new(
        sources: sources.transform_values(&:to_s),
        destination: destination.to_s
      ).run

      expect(destination.join("production.sqlite3")).to be_file
      expect(destination.join("cache.sqlite3")).to be_file
      expect(destination.join("queue.sqlite3")).to be_file
      expect(destination.join("cable.sqlite3")).to be_file

      expect(count_items(destination.join("production.sqlite3"))).to eq(5)
      expect(count_items(destination.join("cache.sqlite3"))).to eq(2)
      expect(count_items(destination.join("queue.sqlite3"))).to eq(3)
      expect(count_items(destination.join("cable.sqlite3"))).to eq(1)

      expect(result.size).to eq(4)
      result.each do |entry|
        expect(entry[:integrity]).to eq("ok")
        expect(entry[:bytes]).to be > 0
        expect(File.exist?(entry[:dest])).to be(true)
      end
      expect(result.map { |e| e[:name] }).to contain_exactly("production", "cache", "queue", "cable")
    end

    it "captures rows that still live in the uncheckpointed WAL of a live writer" do
      source = @tmp.join("production.sqlite3")
      seed_db(source, rows: 3)

      writer = SQLite3::Database.new(source.to_s)
      writer.execute("PRAGMA journal_mode=WAL")
      writer.execute("INSERT INTO items (name) VALUES (?)", [ "wal-row" ])

      destination = @tmp.join("once-pending")
      begin
        described_class.new(
          sources: { "production" => source.to_s },
          destination: destination.to_s
        ).run
      ensure
        writer.close
      end

      expect(count_items(destination.join("production.sqlite3"))).to eq(4)
    end

    it "overwrites a pre-existing snapshot in the destination" do
      source = @tmp.join("production.sqlite3")
      seed_db(source, rows: 1)

      destination = @tmp.join("once-pending")
      FileUtils.mkdir_p(destination)
      stale = destination.join("production.sqlite3")
      File.write(stale, "garbage that is not sqlite")

      described_class.new(
        sources: { "production" => source.to_s },
        destination: destination.to_s
      ).run

      expect(count_items(stale)).to eq(1)
    end

    it "creates the destination directory if it does not exist" do
      source = @tmp.join("production.sqlite3")
      seed_db(source, rows: 1)

      destination = @tmp.join("nested", "once-pending")
      expect(destination).not_to exist

      described_class.new(
        sources: { "production" => source.to_s },
        destination: destination.to_s
      ).run

      expect(destination).to be_directory
      expect(destination.join("production.sqlite3")).to be_file
    end

    it "raises when integrity check does not return ok" do
      source = @tmp.join("production.sqlite3")
      seed_db(source, rows: 1)

      pre_backup = described_class.new(
        sources: { "production" => source.to_s },
        destination: @tmp.join("once-pending").to_s
      )

      # Beams::Backup.snapshot is the shared mechanism; intercepting it here
      # exercises PreBackup's error path without forging a corrupt SQLite file.
      allow(Beams::Backup).to receive(:snapshot).and_return("malformed")

      expect { pre_backup.run }.to raise_error(/integrity/i)
    end
  end

  describe "defaults" do
    it "defaults sources to Beams::Backup.default_sources" do
      require "beams/backup"
      expect(described_class.new.sources).to eq(Beams::Backup.default_sources)
    end

    it "honors ONCE_PRE_BACKUP_DIR for the destination" do
      allow(ENV).to receive(:fetch).and_call_original
      allow(ENV).to receive(:fetch).with("ONCE_PRE_BACKUP_DIR", anything).and_return(@tmp.join("env-dest").to_s)

      pre_backup = described_class.new(sources: { "production" => @tmp.join("absent.sqlite3").to_s })

      expect(pre_backup.destination).to eq(@tmp.join("env-dest").to_s)
    end
  end
end
