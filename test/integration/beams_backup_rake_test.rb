# frozen_string_literal: true

require "test_helper"
require "sqlite3"
require "json"
require "rake"

# Integration test exercising the backup/restore round trip *through the rake
# tasks* defined in lib/tasks/beams.rake.
class BeamsBackupRakeTest < ActionDispatch::IntegrationTest
  # Load the application's rake tasks once.
  Rails.application.load_tasks unless Rake::Task.task_defined?("beams:backup")

  setup do
    @tmpdir = Dir.mktmpdir("beams-rake-spec")
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

  # Re-enable so the same task instance can be invoked again in a later example.
  def run_task(name, *args)
    task = Rake::Task[name]
    task.reenable
    task.invoke(*args)
  end

  def capture_stdout
    original = $stdout
    $stdout = StringIO.new
    yield
    $stdout.string
  ensure
    $stdout = original
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

  test "backs up, lists, then restores via the rake tasks (round trip)" do
    prod = @tmp.join("storage", "production.sqlite3")
    seed_db(prod, rows: 10)

    # --- beams:backup ---------------------------------------------------------
    output = capture_stdout { run_task("beams:backup") }
    assert_match(/Backup created:/, output)

    backup_root = Pathname.new(ENV["BEAMS_BACKUP_DIR"])
    generations = backup_root.children.select(&:directory?).map { |c| c.basename.to_s }
    assert_equal 1, generations.size

    generation = generations.first
    gen_dir = backup_root.join(generation)
    assert_predicate gen_dir.join("production.sqlite3.gz"), :file?
    assert_predicate gen_dir.join("manifest.json"), :file?

    manifest = JSON.parse(gen_dir.join("manifest.json").read)
    assert_equal generation, manifest["timestamp"]

    # --- beams:backup:list ----------------------------------------------------
    output = capture_stdout { run_task("beams:backup:list") }
    assert_match(/#{Regexp.escape(generation)}/, output)

    # --- mutate current DB, then beams:restore[<generation>] ------------------
    seed_db(@tmp.join("storage", "tmp_overwrite.sqlite3"), rows: 1)
    File.delete(prod)
    seed_db(prod, rows: 3) # stale state that should be replaced by the restore
    assert_equal 3, count_items(prod)

    output = capture_stdout { run_task("beams:restore", generation) }
    assert_match(/Restored from generation: #{Regexp.escape(generation)}/, output)

    # data is back to the backed-up state
    assert_equal 10, count_items(prod)

    # a timestamped safety copy of the stale DB was left behind
    safety_copies = @tmp.join("storage").children.map(&:to_s).grep(/production\.sqlite3\..*\.bak\z/)
    assert_equal 1, safety_copies.size
    assert_equal 3, count_items(Pathname.new(safety_copies.first))
  end

  test "beams:backup:list reports when no backups exist" do
    output = capture_stdout { run_task("beams:backup:list") }
    assert_match(/No backups found/, output)
  end

  test "beams:restore without a generation prints usage and available list" do
    output = capture_stdout { run_task("beams:restore") }
    assert_match(/Usage: rake/, output)
  end
end
