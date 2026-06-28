# frozen_string_literal: true

require "test_helper"
require "open3"
require "sqlite3"

# Integration test driving the bin/beams-backup and bin/beams-restore wrappers
# as *real subprocesses* (each one boots Rails via require_relative
# "../config/environment").
class BeamsBinTest < ActionDispatch::IntegrationTest
  def backup_bin
    Rails.root.join("bin", "beams-backup").to_s
  end

  def restore_bin
    Rails.root.join("bin", "beams-restore").to_s
  end

  setup do
    @tmpdir = Dir.mktmpdir("beams-bin-spec")
    @tmp = Pathname.new(@tmpdir)
    FileUtils.mkdir_p(@tmp.join("storage"))
    @backup_dir = @tmp.join("storage", "backups")
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

  def run_bin(script, *args)
    env = {
      "RAILS_ENV" => "test",
      "BEAMS_BACKUP_DIR" => @backup_dir.to_s
    }
    Open3.capture2e(env, RbConfig.ruby, script, *args, chdir: @tmp.to_s)
  end

  test "backs up then restores via the bin wrappers (round trip)" do
    prod = @tmp.join("storage", "production.sqlite3")
    seed_db(prod, rows: 9)

    # --- bin/beams-backup -----------------------------------------------------
    out, status = run_bin(backup_bin)
    assert status.success?, "beams-backup failed:\n#{out}"
    assert_includes out, "Backup created"

    generations = @backup_dir.children.select(&:directory?).map { |c| c.basename.to_s }
    assert_equal 1, generations.size
    generation = generations.first
    assert_predicate @backup_dir.join(generation, "production.sqlite3.gz"), :file?

    # --- mutate, then bin/beams-restore <generation> --------------------------
    File.delete(prod)
    seed_db(prod, rows: 2)
    assert_equal 2, count_items(prod)

    out, status = run_bin(restore_bin, generation)
    assert status.success?, "beams-restore failed:\n#{out}"
    assert_includes out, "Restored from generation: #{generation}"
    assert_includes out, "Next steps"

    assert_equal 9, count_items(prod)
  end

  test "bin/beams-restore with no argument lists generations and exits 1" do
    seed_db(@tmp.join("storage", "production.sqlite3"), rows: 1)
    run_bin(backup_bin)

    out, status = run_bin(restore_bin)
    assert_equal 1, status.exitstatus
    assert_match(/Usage: bin\/beams-restore/, out)
    assert_match(/Available generations:/, out)
  end
end
