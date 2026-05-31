# frozen_string_literal: true

require "sqlite3"
require "zlib"
require "json"
require "time"
require "fileutils"
require "pathname"

require_relative "backup"

module Beams
  # Beams::Restore restores SQLite databases from a backup generation produced
  # by Beams::Backup.
  #
  # Before overwriting a live database the current file is moved aside to a
  # timestamped safety copy (`<db>.<timestamp>.bak`). If any restore step
  # fails, every database touched so far is rolled back from its safety copy so
  # the on-disk state is left as it was before the run.
  #
  # IMPORTANT: restore overwrites database files in place and is intended to be
  # run with the web/worker processes stopped (single-container / ONCE model).
  class Restore
    class GenerationNotFound < StandardError; end

    TIMESTAMP_FORMAT = "%Y%m%dT%H%M%SZ"

    attr_reader :generation, :targets, :backup_dir

    # @param generation [String] generation timestamp or "latest"
    # @param targets [Hash{String=>String}] logical name => destination path
    # @param backup_dir [String] root directory holding generations
    # @param now [Time] timestamp source for safety-copy names (injectable)
    def initialize(generation,
                   targets: self.class.default_targets,
                   backup_dir: ENV.fetch("BEAMS_BACKUP_DIR", Beams::Backup::DEFAULT_BACKUP_DIR),
                   now: Time.now.utc)
      @generation = generation
      @targets = targets
      @backup_dir = backup_dir
      @now = now.utc
    end

    # Restore all matching databases from the resolved generation.
    #
    # @return [Hash] result metadata (resolved timestamp + per-db entries)
    def run
      timestamp = resolve_generation
      generation_dir = File.join(@backup_dir, timestamp)

      done = []
      begin
        entries = @targets.filter_map do |name, target_path|
          gz_path = File.join(generation_dir, "#{name}.sqlite3.gz")
          next unless File.exist?(gz_path)

          restore_one(name, gz_path, target_path, done)
        end
      rescue StandardError
        rollback(done)
        raise
      end

      { timestamp: timestamp, databases: entries }
    end

    # @return [Array<String>] available generations newest first.
    def self.available(backup_dir: ENV.fetch("BEAMS_BACKUP_DIR", Beams::Backup::DEFAULT_BACKUP_DIR))
      Beams::Backup.list(backup_dir: backup_dir)
    end

    # Default destination map mirrors the production database paths.
    #
    # @return [Hash{String=>String}]
    def self.default_targets
      {
        "production" => "storage/production.sqlite3",
        "cache" => "storage/production_cache.sqlite3",
        "queue" => "storage/production_queue.sqlite3",
        "cable" => "storage/production_cable.sqlite3"
      }.transform_values { |p| File.expand_path(p, Dir.pwd) }
    end

    private

    def resolve_generation
      generations = Beams::Backup.list(backup_dir: @backup_dir)
      raise GenerationNotFound, "no backups found in #{@backup_dir}" if generations.empty?

      target = @generation == "latest" ? generations.first : @generation
      unless generations.include?(target)
        raise GenerationNotFound, "generation not found: #{@generation} (in #{@backup_dir})"
      end

      target
    end

    # Restore a single database. The entry (including the safety copy taken
    # before any destructive step) is registered in `done` *immediately* so a
    # failure in a later step can be rolled back.
    def restore_one(name, gz_path, target_path, done)
      FileUtils.mkdir_p(File.dirname(target_path))
      safety_copy = move_aside(target_path)
      entry = { name: name, target: target_path, safety_copy: safety_copy }
      done << entry

      cleanup_sidecars(target_path)
      decompress(gz_path, target_path)

      entry
    end

    # Move the existing db file to a timestamped safety copy. Returns the
    # safety-copy path, or nil when there was no current file.
    def move_aside(target_path)
      return nil unless File.exist?(target_path)

      stamp = @now.strftime(TIMESTAMP_FORMAT)
      safety_copy = "#{target_path}.#{stamp}.bak"
      FileUtils.mv(target_path, safety_copy)
      safety_copy
    end

    # Remove leftover WAL/SHM sidecar files so the restored file is opened clean.
    def cleanup_sidecars(target_path)
      [ "#{target_path}-wal", "#{target_path}-shm" ].each do |f|
        File.delete(f) if File.exist?(f)
      end
    end

    def decompress(gz_path, dest_path)
      Zlib::GzipReader.open(gz_path) do |gz|
        File.open(dest_path, "wb") do |io|
          IO.copy_stream(gz, io)
        end
      end
    end

    def rollback(entries)
      entries.each do |entry|
        target = entry[:target]
        File.delete(target) if File.exist?(target)
        FileUtils.mv(entry[:safety_copy], target) if entry[:safety_copy] && File.exist?(entry[:safety_copy])
      end
    end
  end
end
