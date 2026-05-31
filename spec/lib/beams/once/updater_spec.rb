require "spec_helper"
require_relative "../../../../lib/beams/once/updater"

RSpec.describe Beams::Once::Updater do
  # Records every command array passed to the runner and returns canned stdout
  # keyed by a recognisable fragment of the command.
  class FakeRunner
    attr_reader :calls

    def initialize(responses)
      @responses = responses
      @calls = []
    end

    def call(command)
      @calls << command
      key = @responses.keys.find { |k| command.join(" ").include?(k) }
      @responses.fetch(key, "")
    end
  end

  let(:image) { "ghcr.io/REPLACE_ME/beams:latest" }

  def build(runner)
    described_class.new(runner: runner)
  end

  describe "#update!" do
    context "when the running container already uses the latest image" do
      it "pulls but does not recreate the container and reports updated: false" do
        runner = FakeRunner.new(
          # inspect of the running container's image and the latest image id match
          "inspect --format {{.Image}} beams" => "sha256:aaa\n",
          "inspect --format {{.Id}} #{image}" => "sha256:aaa\n"
        )

        result = build(runner).update!

        commands = runner.calls.map { |c| c.join(" ") }
        expect(commands).to include(a_string_matching(/\Adocker pull #{Regexp.escape(image)}\z/))
        expect(commands).not_to include(a_string_matching(/docker stop beams/))
        expect(commands).not_to include(a_string_matching(/docker rm beams/))
        expect(commands).not_to include(a_string_matching(/docker run /))
        expect(result[:updated]).to be(false)
      end
    end

    context "when a newer image is available" do
      it "pulls, stops, removes and re-runs the container with the shared run args and reports updated: true" do
        runner = FakeRunner.new(
          "inspect --format {{.Image}} beams" => "sha256:old\n",
          "inspect --format {{.Id}} #{image}" => "sha256:new\n"
        )

        result = build(runner).update!

        commands = runner.calls.map { |c| c.join(" ") }
        pull_i  = commands.index { |c| c.start_with?("docker pull") }
        stop_i  = commands.index { |c| c.start_with?("docker stop beams") }
        rm_i    = commands.index { |c| c.start_with?("docker rm beams") }
        run_i   = commands.index { |c| c.start_with?("docker run") }

        expect([ pull_i, stop_i, rm_i, run_i ]).to all(be_a(Integer))
        expect(pull_i).to be < stop_i
        expect(stop_i).to be < rm_i
        expect(rm_i).to be < run_i

        run_command = commands[run_i]
        expect(run_command).to include("--name beams")
        expect(run_command).to include("--restart unless-stopped")
        expect(run_command).to include("-p 80:80")
        expect(run_command).to include("-p 443:443")
        expect(run_command).to include("-v beams_storage:/rails/storage")
        expect(run_command).to include("--env-file /etc/beams/beams.env")
        expect(run_command).to include(image)

        expect(result[:updated]).to be(true)
        expect(result[:current]).to eq("sha256:old")
        expect(result[:latest]).to eq("sha256:new")
      end
    end
  end

  it "shares constants with the installer (image/container/volume/env file/ports)" do
    expect(described_class::IMAGE).to eq("ghcr.io/REPLACE_ME/beams:latest")
    expect(described_class::CONTAINER).to eq("beams")
    expect(described_class::VOLUME).to eq("beams_storage")
    expect(described_class::ENV_FILE).to eq("/etc/beams/beams.env")
  end
end
