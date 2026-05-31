# frozen_string_literal: true

require "rails_helper"
require "open3"
require "sqlite3"

# Integration test driving the bin/beams-backup and bin/beams-restore wrappers
# as *real subprocesses* (each one boots Rails via require_relative
# "../config/environment"). This is the only layer that exercises the wrappers
# end to end, so it is intentionally kept to the minimum number of examples
# because each subprocess pays the full Rails boot cost.
#
# The wrappers resolve the production DB paths against Dir.pwd, so we run the
# subprocesses with chdir into a tmp dir. require_relative is resolved relative
# to the script file, so Rails itself still loads correctly from the repo.
RSpec.describe "beams bin wrappers", type: :integration do
  def backup_bin = Rails.root.join("bin", "beams-backup").to_s
  def restore_bin = Rails.root.join("bin", "beams-restore").to_s

  around do |example|
    Dir.mktmpdir("beams-bin-spec") do |dir|
      @tmp = Pathname.new(dir)
      FileUtils.mkdir_p(@tmp.join("storage"))
      @backup_dir = @tmp.join("storage", "backups")
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

  def run_bin(script, *args)
    env = {
      "RAILS_ENV" => "test",
      "BEAMS_BACKUP_DIR" => @backup_dir.to_s
    }
    Open3.capture2e(env, RbConfig.ruby, script, *args, chdir: @tmp.to_s)
  end

  it "backs up then restores via the bin wrappers (round trip)" do
    prod = @tmp.join("storage", "production.sqlite3")
    seed_db(prod, rows: 9)

    # --- bin/beams-backup -----------------------------------------------------
    out, status = run_bin(backup_bin)
    expect(status).to be_success, "beams-backup failed:\n#{out}"
    expect(out).to include("Backup created")

    generations = @backup_dir.children.select(&:directory?).map { |c| c.basename.to_s }
    expect(generations.size).to eq(1)
    generation = generations.first
    expect(@backup_dir.join(generation, "production.sqlite3.gz")).to be_file

    # --- mutate, then bin/beams-restore <generation> --------------------------
    File.delete(prod)
    seed_db(prod, rows: 2)
    expect(count_items(prod)).to eq(2)

    out, status = run_bin(restore_bin, generation)
    expect(status).to be_success, "beams-restore failed:\n#{out}"
    expect(out).to include("Restored from generation: #{generation}")
    expect(out).to include("Next steps")

    expect(count_items(prod)).to eq(9)
  end

  it "bin/beams-restore with no argument lists generations and exits 1" do
    seed_db(@tmp.join("storage", "production.sqlite3"), rows: 1)
    run_bin(backup_bin)

    out, status = run_bin(restore_bin)
    expect(status.exitstatus).to eq(1)
    expect(out).to match(/Usage: bin\/beams-restore/)
    expect(out).to match(/Available generations:/)
  end
end
