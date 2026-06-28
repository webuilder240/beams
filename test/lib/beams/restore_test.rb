# frozen_string_literal: true

require "test_helper"
require "sqlite3"
require "zlib"
require "json"
require "beams/backup"
require "beams/restore"

class Beams::RestoreTest < ActiveSupport::TestCase
  setup do
    @tmpdir = Dir.mktmpdir("beams-restore-spec")
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

  # --- #run ---
  test "restores the database from the specified generation" do
    source = @tmp.join("source.sqlite3")
    seed_db(source, rows: 8)
    backup_dir = @tmp.join("backups")
    timestamp = make_backup(source, backup_dir)

    target = @tmp.join("production.sqlite3")
    seed_db(target, rows: 1) # stale current db

    restore = Beams::Restore.new(
      timestamp,
      targets: { "production" => target.to_s },
      backup_dir: backup_dir.to_s,
      now: Time.utc(2026, 5, 31, 10, 0, 0)
    )
    restore.run

    assert_equal 8, count_items(target)
  end

  test "moves the current database aside with a timestamped safety copy" do
    source = @tmp.join("source.sqlite3")
    seed_db(source, rows: 4)
    backup_dir = @tmp.join("backups")
    timestamp = make_backup(source, backup_dir)

    target = @tmp.join("production.sqlite3")
    seed_db(target, rows: 99)

    restore = Beams::Restore.new(
      timestamp,
      targets: { "production" => target.to_s },
      backup_dir: backup_dir.to_s,
      now: Time.utc(2026, 5, 31, 10, 0, 0)
    )
    result = restore.run

    safety = result[:databases].first[:safety_copy]
    assert safety
    assert File.exist?(safety)
    assert_equal 99, count_items(Pathname.new(safety))
  end

  test "resolves 'latest' to the newest generation" do
    backup_dir = @tmp.join("backups")

    old_source = @tmp.join("old.sqlite3")
    seed_db(old_source, rows: 2)
    make_backup(old_source, backup_dir, now: Time.utc(2026, 5, 25))

    new_source = @tmp.join("new.sqlite3")
    seed_db(new_source, rows: 7)
    make_backup(new_source, backup_dir, now: Time.utc(2026, 5, 26))

    target = @tmp.join("production.sqlite3")
    restore = Beams::Restore.new(
      "latest",
      targets: { "production" => target.to_s },
      backup_dir: backup_dir.to_s,
      now: Time.utc(2026, 5, 27)
    )
    result = restore.run

    assert_equal "20260526T000000Z", result[:timestamp]
    assert_equal 7, count_items(target)
  end

  test "raises when the generation does not exist" do
    restore = Beams::Restore.new(
      "19990101T000000Z",
      targets: { "production" => @tmp.join("x.sqlite3").to_s },
      backup_dir: @tmp.join("backups").to_s
    )
    assert_raises(Beams::Restore::GenerationNotFound) { restore.run }
  end

  test "rolls back the current database if a restore step fails" do
    source = @tmp.join("source.sqlite3")
    seed_db(source, rows: 5)
    backup_dir = @tmp.join("backups")
    timestamp = make_backup(source, backup_dir)

    target = @tmp.join("production.sqlite3")
    seed_db(target, rows: 42)

    restore = Beams::Restore.new(
      timestamp,
      targets: { "production" => target.to_s },
      backup_dir: backup_dir.to_s,
      now: Time.utc(2026, 5, 31, 10, 0, 0)
    )

    # Force the decompression step to blow up after the safety copy is taken.
    restore.define_singleton_method(:decompress) { |*| raise StandardError, "boom" }

    error = assert_raises(StandardError) { restore.run }
    assert_match(/boom/, error.message)
    # original data must be intact after rollback
    assert_equal 42, count_items(target)
  end

  # --- .available ---
  test "lists generations from the backup directory" do
    source = @tmp.join("source.sqlite3")
    seed_db(source, rows: 1)
    backup_dir = @tmp.join("backups")
    make_backup(source, backup_dir, now: Time.utc(2026, 5, 25))
    make_backup(source, backup_dir, now: Time.utc(2026, 5, 26))

    assert_equal %w[20260526T000000Z 20260525T000000Z],
      Beams::Restore.available(backup_dir: backup_dir.to_s)
  end
end
