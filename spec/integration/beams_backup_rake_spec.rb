# frozen_string_literal: true

require "rails_helper"
require "sqlite3"
require "json"
require "rake"

# Integration test exercising the backup/restore round trip *through the rake
# tasks* defined in lib/tasks/beams.rake (beams:backup / beams:backup:list /
# beams:restore). Unlike the unit specs in spec/lib/beams these drive the same
# code path an operator (or a scheduled job) would use, with the production
# default DB paths resolved relative to Dir.pwd.
#
# Everything happens inside Dir.mktmpdir + Dir.chdir so the real
# storage/*.sqlite3 and storage/backups are never touched.
RSpec.describe "beams rake tasks", type: :task do
  # Load the application's rake tasks exactly once across the whole suite.
  before(:all) do
    Rails.application.load_tasks unless Rake::Task.task_defined?("beams:backup")
  end

  around do |example|
    Dir.mktmpdir("beams-rake-spec") do |dir|
      @tmp = Pathname.new(dir)
      FileUtils.mkdir_p(@tmp.join("storage"))
      Dir.chdir(@tmp) do
        # Default source/target paths are resolved against Dir.pwd, so point the
        # backup dir inside the tmp tree too.
        original = ENV["BEAMS_BACKUP_DIR"]
        ENV["BEAMS_BACKUP_DIR"] = @tmp.join("storage", "backups").to_s
        begin
          example.run
        ensure
          ENV["BEAMS_BACKUP_DIR"] = original
        end
      end
    end
  end

  # Re-enable so the same task instance can be invoked again in a later example.
  def run_task(name, *args)
    task = Rake::Task[name]
    task.reenable
    task.invoke(*args)
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

  it "backs up, lists, then restores via the rake tasks (round trip)" do
    prod = @tmp.join("storage", "production.sqlite3")
    seed_db(prod, rows: 10)

    # --- beams:backup ---------------------------------------------------------
    expect { run_task("beams:backup") }.to output(/Backup created:/).to_stdout

    backup_root = Pathname.new(ENV["BEAMS_BACKUP_DIR"])
    generations = backup_root.children.select(&:directory?).map { |c| c.basename.to_s }
    expect(generations.size).to eq(1)

    generation = generations.first
    gen_dir = backup_root.join(generation)
    expect(gen_dir.join("production.sqlite3.gz")).to be_file
    expect(gen_dir.join("manifest.json")).to be_file

    manifest = JSON.parse(gen_dir.join("manifest.json").read)
    expect(manifest["timestamp"]).to eq(generation)

    # --- beams:backup:list ----------------------------------------------------
    expect { run_task("beams:backup:list") }.to output(/#{Regexp.escape(generation)}/).to_stdout

    # --- mutate current DB, then beams:restore[<generation>] ------------------
    seed_db(@tmp.join("storage", "tmp_overwrite.sqlite3"), rows: 1)
    File.delete(prod)
    seed_db(prod, rows: 3) # stale state that should be replaced by the restore
    expect(count_items(prod)).to eq(3)

    expect { run_task("beams:restore", generation) }
      .to output(/Restored from generation: #{Regexp.escape(generation)}/).to_stdout

    # data is back to the backed-up state
    expect(count_items(prod)).to eq(10)

    # a timestamped safety copy of the stale DB was left behind
    safety_copies = @tmp.join("storage").children.map(&:to_s).grep(/production\.sqlite3\..*\.bak\z/)
    expect(safety_copies.size).to eq(1)
    expect(count_items(Pathname.new(safety_copies.first))).to eq(3)
  end

  it "beams:backup:list reports when no backups exist" do
    expect { run_task("beams:backup:list") }.to output(/No backups found/).to_stdout
  end

  it "beams:restore without a generation prints usage and available list" do
    expect { run_task("beams:restore") }.to output(/Usage: rake/).to_stdout
  end
end
