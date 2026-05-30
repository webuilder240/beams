require "spec_helper"
require_relative "../../../lib/beams/procfile_reader"

RSpec.describe Beams::ProcfileReader do
  describe ".parse" do
    it "returns name-to-command hash for valid entries" do
      content = "web: bundle exec thrust bin/rails server\nworker: bundle exec bin/jobs\n"
      result = described_class.parse(content)
      expect(result).to eq(
        "web" => "bundle exec thrust bin/rails server",
        "worker" => "bundle exec bin/jobs"
      )
    end

    it "handles commands containing colons" do
      content = "web: env KEY=val:extra bundle exec rails s\n"
      result = described_class.parse(content)
      expect(result["web"]).to eq("env KEY=val:extra bundle exec rails s")
    end

    it "ignores blank lines" do
      content = "web: cmd_a\n\nworker: cmd_b\n"
      result = described_class.parse(content)
      expect(result.keys).to contain_exactly("web", "worker")
    end

    it "ignores comment lines" do
      content = "# this is a comment\nweb: cmd\n"
      result = described_class.parse(content)
      expect(result).to eq("web" => "cmd")
    end

    it "returns empty hash for empty content" do
      expect(described_class.parse("")).to eq({})
    end
  end
end
