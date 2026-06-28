# frozen_string_literal: true

require "test_helper"

# The actual snapshot logic lives in Beams::Once::PreBackup and is exercised by
# test/lib/beams/once/pre_backup_test.rb. This test only checks the thin
# wrapper at bin/hooks/pre-backup.
class BinHooksPreBackupTest < ActiveSupport::TestCase
  SCRIPT_PATH = Rails.root.join("bin", "hooks", "pre-backup")

  test "exists" do
    assert File.exist?(SCRIPT_PATH)
  end

  test "is executable (mode 0755)" do
    mode = File.stat(SCRIPT_PATH).mode & 0o777
    assert_equal 0o755, mode
  end

  test "uses a /usr/bin/env ruby shebang" do
    first_line = File.open(SCRIPT_PATH, &:gets)
    assert_equal "#!/usr/bin/env ruby\n", first_line
  end

  test "invokes Beams::Once::PreBackup#run" do
    contents = File.read(SCRIPT_PATH)
    assert_includes contents, "Beams::Once::PreBackup"
    assert_match(/Beams::Once::PreBackup\.new[^\n]*\.run/, contents)
  end

  test "requires the PORO and does not boot Rails" do
    contents = File.read(SCRIPT_PATH)
    assert_includes contents, 'require "beams/once/pre_backup"'
    assert_not_includes contents, "config/environment"
    assert_not_includes contents, "config/application"
  end

  test "chdir's to the repository root so default source paths resolve to /rails/storage" do
    contents = File.read(SCRIPT_PATH)
    assert_match(/Dir\.chdir\(File\.expand_path\("\.\.\/\.\.",\s*__dir__\)\)/, contents)
  end

  test "requires bundler/setup so vendored gems load without Rails boot" do
    contents = File.read(SCRIPT_PATH)
    assert_includes contents, 'require "bundler/setup"'
  end
end
