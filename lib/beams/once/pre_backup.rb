# frozen_string_literal: true

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
    # The actual `VACUUM INTO` + `PRAGMA integrity_check` mechanics are shared
    # with the rake-based generation backup through `Beams::Backup.snapshot`,
    # so both code paths go through identical SQLite handling.
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

        integrity = Beams::Backup.snapshot(source_path: source_path, dest_path: dest_path)
        raise "integrity check failed for #{name}: #{integrity}" unless integrity == "ok"

        {
          name: name,
          source: source_path,
          dest: dest_path,
          bytes: File.size(dest_path),
          integrity: integrity
        }
      end
    end
  end
end
