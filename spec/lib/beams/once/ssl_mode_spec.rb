require "spec_helper"
require_relative "../../../../lib/beams/once/ssl_mode"

RSpec.describe Beams::Once::SslMode do
  describe "#enabled?" do
    context "when DISABLE_SSL is 'true'" do
      it "returns false (SSL disabled)" do
        mode = described_class.new(env: { "DISABLE_SSL" => "true" })
        expect(mode.enabled?).to be false
      end
    end

    context "when DISABLE_SSL is not set" do
      it "returns true (SSL enabled by default)" do
        mode = described_class.new(env: {})
        expect(mode.enabled?).to be true
      end
    end

    context "when DISABLE_SSL is empty string" do
      it "returns true (SSL enabled)" do
        mode = described_class.new(env: { "DISABLE_SSL" => "" })
        expect(mode.enabled?).to be true
      end
    end

    context "when DISABLE_SSL is some other string" do
      it "returns true (SSL enabled)" do
        mode = described_class.new(env: { "DISABLE_SSL" => "false" })
        expect(mode.enabled?).to be true
      end

      it "treats arbitrary values as SSL enabled" do
        mode = described_class.new(env: { "DISABLE_SSL" => "1" })
        expect(mode.enabled?).to be true
      end
    end

    context "when env: is not passed" do
      it "reads from process ENV" do
        allow(ENV).to receive(:[]).and_call_original
        allow(ENV).to receive(:[]).with("DISABLE_SSL").and_return("true")
        mode = described_class.new
        expect(mode.enabled?).to be false
      end
    end
  end

  describe "#ssl_options" do
    it "excludes /up from https redirect" do
      mode = described_class.new(env: {})
      options = mode.ssl_options
      expect(options).to be_a(Hash)
      expect(options[:redirect]).to be_a(Hash)
      exclude = options[:redirect][:exclude]
      expect(exclude).to be_a(Proc)

      up_request = double("request", path: "/up")
      other_request = double("request", path: "/queries")
      expect(exclude.call(up_request)).to be true
      expect(exclude.call(other_request)).to be false
    end

    it "returns ssl_options regardless of DISABLE_SSL value" do
      mode = described_class.new(env: { "DISABLE_SSL" => "true" })
      expect(mode.ssl_options).to be_a(Hash)
      expect(mode.ssl_options.dig(:redirect, :exclude)).to be_a(Proc)
    end
  end
end
