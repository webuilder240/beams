# frozen_string_literal: true

require "test_helper"
require "sqlite3"
require "beams/once/pre_backup"

class Beams::Once::PreBackupTest < ActiveSupport::TestCase
  setup do
    @tmpdir = Dir.mktmpdir("beams-once-pre-backup-spec")
    @tmp = Pathname.new(@tmpdir)
  end

  teardown do
    FileUtils.remove_entry(@tmpdir) if @tmpdir && File.exist?(@tmpdir)
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

  # --- #run ---
  test "writes a consistent snapshot of every source database to the destination" do
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
    result = Beams::Once::PreBackup.new(
      sources: sources.transform_values(&:to_s),
      destination: destination.to_s
    ).run

    assert_predicate destination.join("production.sqlite3"), :file?
    assert_predicate destination.join("cache.sqlite3"), :file?
    assert_predicate destination.join("queue.sqlite3"), :file?
    assert_predicate destination.join("cable.sqlite3"), :file?

    assert_equal 5, count_items(destination.join("production.sqlite3"))
    assert_equal 2, count_items(destination.join("cache.sqlite3"))
    assert_equal 3, count_items(destination.join("queue.sqlite3"))
    assert_equal 1, count_items(destination.join("cable.sqlite3"))

    assert_equal 4, result.size
    result.each do |entry|
      assert_equal "ok", entry[:integrity]
      assert entry[:bytes] > 0
      assert_equal true, File.exist?(entry[:dest])
    end
    assert_equal %w[cable cache production queue], result.map { |e| e[:name] }.sort
  end

  test "captures rows that still live in the uncheckpointed WAL of a live writer" do
    source = @tmp.join("production.sqlite3")
    seed_db(source, rows: 3)

    writer = SQLite3::Database.new(source.to_s)
    writer.execute("PRAGMA journal_mode=WAL")
    writer.execute("INSERT INTO items (name) VALUES (?)", [ "wal-row" ])

    destination = @tmp.join("once-pending")
    begin
      Beams::Once::PreBackup.new(
        sources: { "production" => source.to_s },
        destination: destination.to_s
      ).run
    ensure
      writer.close
    end

    assert_equal 4, count_items(destination.join("production.sqlite3"))
  end

  test "overwrites a pre-existing snapshot in the destination" do
    source = @tmp.join("production.sqlite3")
    seed_db(source, rows: 1)

    destination = @tmp.join("once-pending")
    FileUtils.mkdir_p(destination)
    stale = destination.join("production.sqlite3")
    File.write(stale, "garbage that is not sqlite")

    Beams::Once::PreBackup.new(
      sources: { "production" => source.to_s },
      destination: destination.to_s
    ).run

    assert_equal 1, count_items(stale)
  end

  test "creates the destination directory if it does not exist" do
    source = @tmp.join("production.sqlite3")
    seed_db(source, rows: 1)

    destination = @tmp.join("nested", "once-pending")
    assert_not destination.exist?

    Beams::Once::PreBackup.new(
      sources: { "production" => source.to_s },
      destination: destination.to_s
    ).run

    assert_predicate destination, :directory?
    assert_predicate destination.join("production.sqlite3"), :file?
  end

  test "raises when integrity check does not return ok" do
    source = @tmp.join("production.sqlite3")
    seed_db(source, rows: 1)

    pre_backup = Beams::Once::PreBackup.new(
      sources: { "production" => source.to_s },
      destination: @tmp.join("once-pending").to_s
    )

    # Beams::Backup.snapshot is the shared mechanism; intercepting it here
    # exercises PreBackup's error path without forging a corrupt SQLite file.
    Beams::Backup.stub(:snapshot, "malformed") do
      error = assert_raises(StandardError) { pre_backup.run }
      assert_match(/integrity/i, error.message)
    end
  end

  # --- defaults ---
  test "defaults sources to Beams::Backup.default_sources" do
    require "beams/backup"
    assert_equal Beams::Backup.default_sources, Beams::Once::PreBackup.new.sources
  end

  test "honors ONCE_PRE_BACKUP_DIR for the destination" do
    env_dest = @tmp.join("env-dest").to_s
    original = ENV["ONCE_PRE_BACKUP_DIR"]
    ENV["ONCE_PRE_BACKUP_DIR"] = env_dest
    begin
      pre_backup = Beams::Once::PreBackup.new(sources: { "production" => @tmp.join("absent.sqlite3").to_s })
      assert_equal env_dest, pre_backup.destination
    ensure
      ENV["ONCE_PRE_BACKUP_DIR"] = original
    end
  end
end
