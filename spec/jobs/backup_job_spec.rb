# frozen_string_literal: true

require "rails_helper"

RSpec.describe BackupJob do
  it "runs a single backup generation via Beams::Backup" do
    backup = instance_double(Beams::Backup, run: { dir: "/tmp/x", timestamp: "20260531T090000Z", databases: [] })
    allow(Beams::Backup).to receive(:new).and_return(backup)

    described_class.perform_now

    expect(Beams::Backup).to have_received(:new)
    expect(backup).to have_received(:run)
  end
end
