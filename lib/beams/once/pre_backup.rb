# frozen_string_literal: true

require "sqlite3"
require "fileutils"
require "beams/backup"

module Beams
  module Once
    # Beams::Once::PreBackup is invoked from the `/hooks/pre-backup` hook that
    # basecamp/once calls before taking a backup. It writes a consistent
    # single-file snapshot of every Beams SQLite database to a single
    # destination directory (default `/storage/backups/once-pending/`). ONCE
    # then picks the directory up and folds it into its own generation
    # management; we deliberately do NOT manage generations or manifests here.
    #
    # Snapshots are produced with `VACUUM INTO`, which yields a transactionally
    # consistent copy even on a live, WAL-mode database. We use the same
    # mechanism as Beams::Backup for the same reason: the optional
    # SQLite3::Database#backup C-API is not present in every build of the
    # sqlite3 gem, while `VACUUM INTO` is universally available.
    class PreBackup
      DEFAULT_DESTINATION = "/storage/backups/once-pending"

      attr_reader :sources, :destination

      # @param sources [Hash{String=>String}] logical name => source sqlite path
      # @param destination [String] directory to receive the snapshots
      def initialize(sources: Beams::Backup.default_sources,
                     destination: ENV.fetch("ONCE_PRE_BACKUP_DIR", DEFAULT_DESTINATION))
        @sources = sources
        @destination = destination
      end

      # Run one snapshot pass over every configured source.
      #
      # @return [Array<Hash>] one entry per source database with keys
      #   `:name`, `:source`, `:dest`, `:bytes`, `:integrity`.
      def run
        FileUtils.mkdir_p(@destination)

        @sources.filter_map do |name, source_path|
          next unless File.exist?(source_path)

          snapshot(name, source_path)
        end
      end

      private

      def snapshot(name, source_path)
        dest_path = File.join(@destination, "#{name}.sqlite3")

        online_backup(source_path, dest_path)
        integrity = integrity_check(dest_path)
        raise "integrity check failed for #{name}: #{integrity}" unless integrity == "ok"

        {
          name: name,
          source: source_path,
          dest: dest_path,
          bytes: File.size(dest_path),
          integrity: integrity
        }
      end

      # Take a consistent single-file snapshot using `VACUUM INTO`. See the
      # class doc for the rationale (matches Beams::Backup).
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
    end
  end
end
