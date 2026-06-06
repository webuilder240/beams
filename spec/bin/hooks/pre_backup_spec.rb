# frozen_string_literal: true

require "rails_helper"

# The actual snapshot logic lives in Beams::Once::PreBackup and is exercised by
# spec/lib/beams/once/pre_backup_spec.rb. This spec only checks the thin
# wrapper at bin/hooks/pre-backup so we don't have to spin up a real ruby
# subprocess from the test suite (subprocess invocation with a fully
# substituted ENV is fragile inside RSpec). What we need to guarantee is:
#
# 1. The script exists and is executable (mode 0755) so basecamp/once will
#    actually invoke it.
# 2. It uses a `#!/usr/bin/env ruby` shebang so it can run without Rails
#    being booted (ONCE invokes the hook directly).
# 3. It actually calls Beams::Once::PreBackup#run so the hook does something.
RSpec.describe "bin/hooks/pre-backup" do
  let(:script_path) { Rails.root.join("bin", "hooks", "pre-backup") }

  it "exists" do
    expect(File).to exist(script_path)
  end

  it "is executable (mode 0755)" do
    mode = File.stat(script_path).mode & 0o777
    expect(mode).to eq(0o755)
  end

  it "uses a /usr/bin/env ruby shebang" do
    first_line = File.open(script_path, &:gets)
    expect(first_line).to eq("#!/usr/bin/env ruby\n")
  end

  it "invokes Beams::Once::PreBackup#run" do
    contents = File.read(script_path)
    expect(contents).to include("Beams::Once::PreBackup")
    expect(contents).to match(/Beams::Once::PreBackup\.new[^\n]*\.run/)
  end

  it "requires the PORO and does not boot Rails" do
    contents = File.read(script_path)
    expect(contents).to include('require "beams/once/pre_backup"')
    expect(contents).not_to include("config/environment")
    expect(contents).not_to include("config/application")
  end

  it "chdir's to the repository root so default source paths resolve to /rails/storage" do
    # Beams::Backup.default_sources expands paths from Dir.pwd, so the hook
    # must move to the repo root (the parent of bin/) before invoking it.
    # ONCE may set an arbitrary cwd; relying on Dir.pwd as supplied by the
    # caller would silently produce empty backups.
    contents = File.read(script_path)
    expect(contents).to match(/Dir\.chdir\(File\.expand_path\("\.\.\/\.\.",\s*__dir__\)\)/)
  end

  it "requires bundler/setup so vendored gems load without Rails boot" do
    contents = File.read(script_path)
    expect(contents).to include('require "bundler/setup"')
  end
end
