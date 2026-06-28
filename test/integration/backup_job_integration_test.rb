# frozen_string_literal: true

require "test_helper"
require "sqlite3"
require "json"

# Integration test that runs BackupJob *without mocking* Beams::Backup, so the
# job genuinely produces a backup generation on disk.
class BackupJobIntegrationTest < ActionDispatch::IntegrationTest
  setup do
    @tmpdir = Dir.mktmpdir("beams-backup-job-spec")
    @tmp = Pathname.new(@tmpdir)
    FileUtils.mkdir_p(@tmp.join("storage"))
    @original_cwd = Dir.pwd
    @original_env = ENV["BEAMS_BACKUP_DIR"]
    ENV["BEAMS_BACKUP_DIR"] = @tmp.join("storage", "backups").to_s
    Dir.chdir(@tmp.to_s)
  end

  teardown do
    Dir.chdir(@original_cwd) if @original_cwd
    ENV["BEAMS_BACKUP_DIR"] = @original_env
    FileUtils.remove_entry(@tmpdir) if @tmpdir && File.exist?(@tmpdir)
  end

  def seed_db(path, rows:)
    SQLite3::Database.new(path.to_s) do |db|
      db.execute("CREATE TABLE items (id INTEGER PRIMARY KEY, name TEXT)")
      rows.times { |i| db.execute("INSERT INTO items (name) VALUES (?)", [ "item-#{i}" ]) }
    end
  end

  test "actually creates one backup generation on disk" do
    seed_db(@tmp.join("storage", "production.sqlite3"), rows: 6)

    result = BackupJob.perform_now

    backup_root = Pathname.new(ENV["BEAMS_BACKUP_DIR"])
    generations = backup_root.children.select(&:directory?).map { |c| c.basename.to_s }
    assert_equal 1, generations.size

    gen_dir = backup_root.join(generations.first)
    assert_predicate gen_dir.join("production.sqlite3.gz"), :file?
    assert_predicate gen_dir.join("manifest.json"), :file?
    assert_equal gen_dir.to_s, result[:dir]

    entry = result[:databases].find { |d| d[:name] == "production" }
    assert_equal "ok", entry[:integrity]
  end
end
