# frozen_string_literal: true

namespace :beams do
  desc "Create one SQLite backup generation under BEAMS_BACKUP_DIR"
  task backup: :environment do
    require "beams/backup"
    result = Beams::Backup.new.run
    puts "Backup created: #{result[:dir]}"
    result[:databases].each do |db|
      puts "  #{db[:name]}: #{db[:file]} (#{db[:bytes]} bytes, integrity=#{db[:integrity]})"
    end
  end

  namespace :backup do
    desc "List available backup generations (newest first)"
    task list: :environment do
      require "beams/backup"
      generations = Beams::Backup.list
      if generations.empty?
        puts "No backups found in #{ENV.fetch('BEAMS_BACKUP_DIR', Beams::Backup::DEFAULT_BACKUP_DIR)}"
      else
        generations.each { |g| puts g }
      end
    end
  end

  desc "Restore SQLite databases from a backup generation: rake 'beams:restore[<timestamp|latest>]'"
  task :restore, [ :generation ] => :environment do |_task, args|
    require "beams/restore"
    generation = args[:generation]
    if generation.blank?
      puts "Usage: rake 'beams:restore[<timestamp>|latest]'"
      puts "Available generations:"
      Beams::Restore.available.each { |g| puts "  #{g}" }
      next
    end

    result = Beams::Restore.new(generation).run
    puts "Restored from generation: #{result[:timestamp]}"
    result[:databases].each do |db|
      puts "  #{db[:name]} -> #{db[:target]} (safety copy: #{db[:safety_copy] || 'none'})"
    end
  end
end
