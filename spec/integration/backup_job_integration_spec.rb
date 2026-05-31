# frozen_string_literal: true

require "rails_helper"
require "sqlite3"
require "json"

# Integration test that runs BackupJob *without mocking* Beams::Backup, so the
# job genuinely produces a backup generation on disk. The existing
# spec/jobs/backup_job_spec.rb keeps its mock-based example (it only asserts the
# wiring); this one asserts the real side effect.
#
# Default source paths are resolved against Dir.pwd, so the whole thing runs
# inside Dir.mktmpdir + Dir.chdir to keep real storage/*.sqlite3 untouched.
RSpec.describe BackupJob, type: :job do
  around do |example|
    Dir.mktmpdir("beams-backup-job-spec") do |dir|
      @tmp = Pathname.new(dir)
      FileUtils.mkdir_p(@tmp.join("storage"))
      Dir.chdir(@tmp) do
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

  def seed_db(path, rows:)
    SQLite3::Database.new(path.to_s) do |db|
      db.execute("CREATE TABLE items (id INTEGER PRIMARY KEY, name TEXT)")
      rows.times { |i| db.execute("INSERT INTO items (name) VALUES (?)", [ "item-#{i}" ]) }
    end
  end

  it "actually creates one backup generation on disk" do
    seed_db(@tmp.join("storage", "production.sqlite3"), rows: 6)

    result = described_class.perform_now

    backup_root = Pathname.new(ENV["BEAMS_BACKUP_DIR"])
    generations = backup_root.children.select(&:directory?).map { |c| c.basename.to_s }
    expect(generations.size).to eq(1)

    gen_dir = backup_root.join(generations.first)
    expect(gen_dir.join("production.sqlite3.gz")).to be_file
    expect(gen_dir.join("manifest.json")).to be_file
    expect(result[:dir]).to eq(gen_dir.to_s)

    entry = result[:databases].find { |d| d[:name] == "production" }
    expect(entry[:integrity]).to eq("ok")
  end
end
