require "rails_helper"

RSpec.describe ApplicationSetting, type: :model do
  describe ".instance (singleton)" do
    it "creates the row on first access with the default rate" do
      expect {
        expect(described_class.instance.bigquery_yen_per_tb).to eq(950.0)
      }.to change(described_class, :count).by(1)
    end

    it "returns the same single row on subsequent access" do
      first = described_class.instance
      second = described_class.instance
      expect(second.id).to eq(first.id)
      expect(described_class.count).to eq(1)
    end
  end

  describe "validations" do
    it "is valid with the default" do
      expect(described_class.new(bigquery_yen_per_tb: 950.0)).to be_valid
    end

    it "allows zero" do
      expect(described_class.new(bigquery_yen_per_tb: 0)).to be_valid
    end

    it "rejects a negative rate" do
      setting = described_class.new(bigquery_yen_per_tb: -1)
      expect(setting).not_to be_valid
      expect(setting.errors[:bigquery_yen_per_tb]).to be_present
    end

    it "rejects a non-numeric rate" do
      setting = described_class.new(bigquery_yen_per_tb: "abc")
      expect(setting).not_to be_valid
      expect(setting.errors[:bigquery_yen_per_tb]).to be_present
    end

    it "requires a rate (NOT NULL)" do
      setting = described_class.new(bigquery_yen_per_tb: nil)
      expect(setting).not_to be_valid
      expect(setting.errors[:bigquery_yen_per_tb]).to be_present
    end
  end

  describe "allowed_email_domain" do
    let(:setting) { described_class.new(bigquery_yen_per_tb: 950.0) }

    it "is valid when blank (OAuth 自動プロビジョニング無効)" do
      setting.allowed_email_domain = nil
      expect(setting).to be_valid
      setting.allowed_email_domain = ""
      expect(setting).to be_valid
    end

    it "accepts a simple domain like example.com" do
      setting.allowed_email_domain = "example.com"
      expect(setting).to be_valid
    end

    it "accepts a multi-level domain" do
      setting.allowed_email_domain = "corp.example.co.jp"
      expect(setting).to be_valid
    end

    it "rejects values with a leading @" do
      setting.allowed_email_domain = "@example.com"
      expect(setting).not_to be_valid
      expect(setting.errors[:allowed_email_domain]).to be_present
    end

    it "rejects values with whitespace" do
      setting.allowed_email_domain = "exa mple.com"
      expect(setting).not_to be_valid
    end

    it "rejects a value without a dot" do
      setting.allowed_email_domain = "example"
      expect(setting).not_to be_valid
    end
  end
end
