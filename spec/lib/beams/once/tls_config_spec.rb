require "spec_helper"
require_relative "../../../../lib/beams/once/tls_config"

RSpec.describe Beams::Once::TlsConfig do
  describe "#enabled?" do
    it "is true when TLS_DOMAIN is present" do
      config = described_class.new(env: { "TLS_DOMAIN" => "beams.example.com" })
      expect(config.enabled?).to be(true)
    end

    it "is false when TLS_DOMAIN is missing" do
      config = described_class.new(env: {})
      expect(config.enabled?).to be(false)
    end

    it "is false when TLS_DOMAIN is blank" do
      config = described_class.new(env: { "TLS_DOMAIN" => "   " })
      expect(config.enabled?).to be(false)
    end

    it "defaults to the process ENV when no env is injected" do
      expect(described_class.new.enabled?).to eq(!ENV["TLS_DOMAIN"].to_s.strip.empty?)
    end
  end

  describe "#ssl_options" do
    let(:config) { described_class.new(env: { "TLS_DOMAIN" => "beams.example.com" }) }

    it "excludes the /up health check from the https redirect" do
      exclude = config.ssl_options.dig(:redirect, :exclude)
      up_request = double("request", path: "/up")
      expect(exclude.call(up_request)).to be(true)
    end

    it "does not exclude other paths from the https redirect" do
      exclude = config.ssl_options.dig(:redirect, :exclude)
      other_request = double("request", path: "/queries")
      expect(exclude.call(other_request)).to be(false)
    end
  end
end
