# frozen_string_literal: true

require "test_helper"
require "sqlite3"
require "zlib"
require "json"
require "beams/backup"

class Beams::BackupTest < ActiveSupport::TestCase
  setup do
    @tmpdir = Dir.mktmpdir("beams-backup-spec")
    @tmp = Pathname.new(@tmpdir)
  end

  teardown do
    FileUtils.remove_entry(@tmpdir) if @tmpdir && File.exist?(@tmpdir)
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

  # --- #run ---
  test "creates a timestamped backup directory containing a gzip snapshot" do
    source = @tmp.join("production.sqlite3")
    seed_db(source, rows: 5)

    backup = Beams::Backup.new(
      sources: { "production" => source.to_s },
      backup_dir: @tmp.join("backups").to_s,
      generations: 7,
      now: Time.utc(2026, 5, 31, 9, 0, 0)
    )
    result = backup.run

    generation_dir = @tmp.join("backups", "20260531T090000Z")
    assert_predicate generation_dir, :directory?
    assert_predicate generation_dir.join("production.sqlite3.gz"), :file?
    assert_equal generation_dir.to_s, result[:dir]
  end

  test "produces a snapshot whose data matches the source" do
    source = @tmp.join("production.sqlite3")
    seed_db(source, rows: 12)

    backup = Beams::Backup.new(
      sources: { "production" => source.to_s },
      backup_dir: @tmp.join("backups").to_s
    )
    result = backup.run

    gz = Pathname.new(result[:dir]).join("production.sqlite3.gz")
    restored = @tmp.join("restored.sqlite3")
    gunzip(gz, restored)

    assert_equal 12, count_items(restored)
  end

  test "captures data even while the source has uncheckpointed WAL writes" do
    source = @tmp.join("production.sqlite3")
    seed_db(source, rows: 3)

    writer = SQLite3::Database.new(source.to_s)
    writer.execute("PRAGMA journal_mode=WAL")
    writer.execute("INSERT INTO items (name) VALUES (?)", [ "wal-row" ])

    begin
      backup = Beams::Backup.new(
        sources: { "production" => source.to_s },
        backup_dir: @tmp.join("backups").to_s
      )
      result = backup.run

      gz = Pathname.new(result[:dir]).join("production.sqlite3.gz")
      restored = @tmp.join("restored.sqlite3")
      gunzip(gz, restored)

      assert_equal 4, count_items(restored)
    ensure
      writer.close
    end
  end

  test "records a manifest with integrity check results" do
    source = @tmp.join("production.sqlite3")
    seed_db(source, rows: 2)

    backup = Beams::Backup.new(
      sources: { "production" => source.to_s },
      backup_dir: @tmp.join("backups").to_s,
      now: Time.utc(2026, 5, 31, 9, 0, 0)
    )
    result = backup.run

    manifest_path = Pathname.new(result[:dir]).join("manifest.json")
    assert_predicate manifest_path, :file?

    manifest = JSON.parse(manifest_path.read)
    assert_equal "20260531T090000Z", manifest["timestamp"]
    entry = manifest["databases"].find { |d| d["name"] == "production" }
    assert_equal "ok", entry["integrity"]
    assert entry["bytes"] > 0
  end

  test "skips sources whose files do not exist" do
    source = @tmp.join("production.sqlite3")
    seed_db(source, rows: 1)

    backup = Beams::Backup.new(
      sources: {
        "production" => source.to_s,
        "cache" => @tmp.join("missing.sqlite3").to_s
      },
      backup_dir: @tmp.join("backups").to_s
    )
    result = backup.run

    names = result[:databases].map { |d| d[:name] }
    assert_equal [ "production" ], names
    assert_not Pathname.new(result[:dir]).join("cache.sqlite3.gz").exist?
  end

  # --- generation rotation ---
  test "keeps only the configured number of newest generations" do
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
      Beams::Backup.new(
        sources: { "production" => source.to_s },
        backup_dir: backup_dir.to_s,
        generations: 3,
        now: t
      ).run
    end

    remaining = backup_dir.children.select(&:directory?).map(&:basename).map(&:to_s).sort
    assert_equal %w[20260526T010000Z 20260527T010000Z 20260528T010000Z], remaining
  end

  # --- .list ---
  test "returns existing generation timestamps newest first" do
    source = @tmp.join("production.sqlite3")
    seed_db(source, rows: 1)
    backup_dir = @tmp.join("backups")

    [ Time.utc(2026, 5, 25), Time.utc(2026, 5, 26) ].each do |t|
      Beams::Backup.new(
        sources: { "production" => source.to_s },
        backup_dir: backup_dir.to_s,
        now: t
      ).run
    end

    assert_equal %w[20260526T000000Z 20260525T000000Z],
      Beams::Backup.list(backup_dir: backup_dir.to_s)
  end

  test "returns an empty array when the backup dir is absent" do
    assert_equal [], Beams::Backup.list(backup_dir: @tmp.join("nope").to_s)
  end

  # --- configuration via environment ---
  test "reads backup_dir and generations from ENV by default" do
    env_backup_dir = @tmp.join("env-backups").to_s
    original_env_dir = ENV["BEAMS_BACKUP_DIR"]
    original_env_gens = ENV["BEAMS_BACKUP_GENERATIONS"]
    ENV["BEAMS_BACKUP_DIR"] = env_backup_dir
    ENV["BEAMS_BACKUP_GENERATIONS"] = "4"
    begin
      backup = Beams::Backup.new(sources: { "production" => @tmp.join("x.sqlite3").to_s })

      assert_equal env_backup_dir, backup.backup_dir
      assert_equal 4, backup.generations
    ensure
      ENV["BEAMS_BACKUP_DIR"] = original_env_dir
      ENV["BEAMS_BACKUP_GENERATIONS"] = original_env_gens
    end
  end

  # --- .snapshot ---
  test "writes a single-file VACUUM INTO copy at dest_path and returns the integrity result" do
    source = @tmp.join("production.sqlite3")
    seed_db(source, rows: 4)

    dest = @tmp.join("snapshot.sqlite3")
    integrity = Beams::Backup.snapshot(source_path: source.to_s, dest_path: dest.to_s)

    assert_predicate dest, :file?
    assert_equal 4, count_items(dest)
    assert_equal "ok", integrity
  end

  test "overwrites a pre-existing file at dest_path" do
    source = @tmp.join("production.sqlite3")
    seed_db(source, rows: 1)
    dest = @tmp.join("snapshot.sqlite3")
    File.write(dest, "garbage")

    Beams::Backup.snapshot(source_path: source.to_s, dest_path: dest.to_s)

    assert_equal 1, count_items(dest)
  end

  test "captures rows still living in the uncheckpointed WAL of a live writer" do
    source = @tmp.join("production.sqlite3")
    seed_db(source, rows: 2)

    writer = SQLite3::Database.new(source.to_s)
    writer.execute("PRAGMA journal_mode=WAL")
    writer.execute("INSERT INTO items (name) VALUES (?)", [ "wal-row" ])

    dest = @tmp.join("snapshot.sqlite3")
    begin
      Beams::Backup.snapshot(source_path: source.to_s, dest_path: dest.to_s)
    ensure
      writer.close
    end

    assert_equal 3, count_items(dest)
  end
end
