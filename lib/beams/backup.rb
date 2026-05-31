# frozen_string_literal: true

require "sqlite3"
require "zlib"
require "json"
require "time"
require "fileutils"
require "pathname"

module Beams
  # Beams::Backup takes consistent online snapshots of SQLite databases.
  #
  # Each invocation creates a timestamped generation directory under the
  # configured backup directory, e.g. `<backup_dir>/20260531T090000Z/`, that
  # contains one gzip-compressed snapshot per source database plus a
  # `manifest.json` describing the run. Old generations beyond the configured
  # retention count are pruned automatically.
  #
  # Snapshots are produced with SQLite's online backup API
  # (`SQLite3::Database#backup`), which yields a single-file, transactionally
  # consistent copy even while the source is being written to in WAL mode.
  class Backup
    DEFAULT_BACKUP_DIR = "storage/backups"
    DEFAULT_GENERATIONS = 7
    TIMESTAMP_FORMAT = "%Y%m%dT%H%M%SZ"

    attr_reader :sources, :backup_dir, :generations

    # @param sources [Hash{String=>String}] logical name => source sqlite path
    # @param backup_dir [String] root directory for generations
    # @param generations [Integer] number of newest generations to retain
    # @param now [Time] timestamp source (injected for deterministic tests)
    def initialize(sources: self.class.default_sources,
                   backup_dir: ENV.fetch("BEAMS_BACKUP_DIR", DEFAULT_BACKUP_DIR),
                   generations: Integer(ENV.fetch("BEAMS_BACKUP_GENERATIONS", DEFAULT_GENERATIONS)),
                   now: Time.now.utc)
      @sources = sources
      @backup_dir = backup_dir
      @generations = generations
      @now = now.utc
    end

    # Execute one backup generation and prune old generations.
    #
    # @return [Hash] result metadata including the generation directory and
    #   per-database entries.
    def run
      timestamp = @now.strftime(TIMESTAMP_FORMAT)
      generation_dir = File.join(@backup_dir, timestamp)
      FileUtils.mkdir_p(generation_dir)

      entries = @sources.filter_map do |name, source_path|
        next unless File.exist?(source_path)

        snapshot(name, source_path, generation_dir)
      end

      write_manifest(generation_dir, timestamp, entries)
      rotate

      { dir: generation_dir, timestamp: timestamp, databases: entries }
    end

    # @return [Array<String>] existing generation timestamps, newest first.
    def self.list(backup_dir: ENV.fetch("BEAMS_BACKUP_DIR", DEFAULT_BACKUP_DIR))
      root = Pathname.new(backup_dir)
      return [] unless root.directory?

      root.children
          .select(&:directory?)
          .map { |c| c.basename.to_s }
          .sort
          .reverse
    end

    # Default source map derived from the production database configuration.
    #
    # @return [Hash{String=>String}]
    def self.default_sources
      paths = {
        "production" => "storage/production.sqlite3",
        "cache" => "storage/production_cache.sqlite3",
        "queue" => "storage/production_queue.sqlite3",
        "cable" => "storage/production_cable.sqlite3"
      }
      paths.transform_values { |p| File.expand_path(p, Dir.pwd) }
    end

    private

    def snapshot(name, source_path, generation_dir)
      raw_path = File.join(generation_dir, "#{name}.sqlite3")
      gz_path = "#{raw_path}.gz"

      online_backup(source_path, raw_path)
      integrity = integrity_check(raw_path)
      compress(raw_path, gz_path)
      File.delete(raw_path)

      bytes = File.size(gz_path)
      raise "integrity check failed for #{name}: #{integrity}" unless integrity == "ok"

      { name: name, file: File.basename(gz_path), bytes: bytes, integrity: integrity }
    end

    # Take a consistent single-file snapshot using `VACUUM INTO`. This works on
    # a live, WAL-mode database (uncheckpointed WAL pages are included) and does
    # not depend on the optional SQLite3::Database#backup API, which is not
    # available in every build of the sqlite3 gem.
    def online_backup(source_path, dest_path)
      File.delete(dest_path) if File.exist?(dest_path)
      source = SQLite3::Database.new(source_path)
      source.execute("VACUUM INTO ?", [ dest_path ])
    ensure
      source&.close
    end

    def integrity_check(sqlite_path)
      db = SQLite3::Database.new(sqlite_path)
      db.get_first_value("PRAGMA integrity_check")
    ensure
      db&.close
    end

    def compress(raw_path, gz_path)
      Zlib::GzipWriter.open(gz_path) do |gz|
        File.open(raw_path, "rb") do |io|
          IO.copy_stream(io, gz)
        end
      end
    end

    def write_manifest(generation_dir, timestamp, entries)
      manifest = {
        "timestamp" => timestamp,
        "created_at" => @now.iso8601,
        "databases" => entries.map { |e| e.transform_keys(&:to_s) }
      }
      File.write(File.join(generation_dir, "manifest.json"), JSON.pretty_generate(manifest))
    end

    def rotate
      generations = self.class.list(backup_dir: @backup_dir)
      generations.drop(@generations).each do |stale|
        FileUtils.rm_rf(File.join(@backup_dir, stale))
      end
    end
  end
end
