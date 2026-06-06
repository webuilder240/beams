require "rails_helper"

RSpec.describe RedashSource, type: :model do
  let(:valid_attributes) do
    {
      name: "社内 Redash",
      url: "https://redash.example.com",
      api_key: "dummy_api_key_12345"
    }
  end

  # 既定では Resolv.getaddresses をスタブして「グローバル IP」に解決させ、
  # SSRF ガードを通過させる。バリデーション失敗を検証するケースだけ個別に再スタブする。
  before do
    allow(Resolv).to receive(:getaddresses).and_return([ "203.0.113.10" ])
  end

  describe "validations" do
    it "is valid with name, https url, and api_key" do
      expect(RedashSource.new(valid_attributes)).to be_valid
    end

    it "requires name" do
      record = RedashSource.new(valid_attributes.merge(name: ""))
      expect(record).not_to be_valid
      expect(record.errors[:name]).to be_present
    end

    it "requires url" do
      record = RedashSource.new(valid_attributes.merge(url: ""))
      expect(record).not_to be_valid
      expect(record.errors[:url]).to be_present
    end

    it "requires api_key" do
      record = RedashSource.new(valid_attributes.merge(api_key: ""))
      expect(record).not_to be_valid
      expect(record.errors[:api_key]).to be_present
    end

    it "rejects duplicate name" do
      RedashSource.create!(valid_attributes)
      duplicate = RedashSource.new(valid_attributes.merge(url: "https://other.example.com"))
      expect(duplicate).not_to be_valid
      expect(duplicate.errors[:name]).to be_present
    end

    it "rejects http scheme" do
      record = RedashSource.new(valid_attributes.merge(url: "http://redash.example.com"))
      expect(record).not_to be_valid
      expect(record.errors[:url]).to be_present
    end

    it "rejects file scheme" do
      record = RedashSource.new(valid_attributes.merge(url: "file:///etc/passwd"))
      expect(record).not_to be_valid
      expect(record.errors[:url]).to be_present
    end

    it "rejects ftp scheme" do
      record = RedashSource.new(valid_attributes.merge(url: "ftp://redash.example.com"))
      expect(record).not_to be_valid
      expect(record.errors[:url]).to be_present
    end

    it "rejects malformed url" do
      record = RedashSource.new(valid_attributes.merge(url: "not a url"))
      expect(record).not_to be_valid
      expect(record.errors[:url]).to be_present
    end

    it "rejects url without host" do
      record = RedashSource.new(valid_attributes.merge(url: "https://"))
      expect(record).not_to be_valid
      expect(record.errors[:url]).to be_present
    end

    it "rejects loopback host (127.0.0.1)" do
      record = RedashSource.new(valid_attributes.merge(url: "https://127.0.0.1"))
      allow(Resolv).to receive(:getaddresses).and_return([ "127.0.0.1" ])
      expect(record).not_to be_valid
      expect(record.errors[:url]).to be_present
    end

    it "rejects private host (10.0.0.5)" do
      record = RedashSource.new(valid_attributes.merge(url: "https://internal.example.com"))
      allow(Resolv).to receive(:getaddresses).and_return([ "10.0.0.5" ])
      expect(record).not_to be_valid
      expect(record.errors[:url]).to be_present
    end

    it "rejects link-local metadata host (169.254.169.254)" do
      record = RedashSource.new(valid_attributes.merge(url: "https://metadata.google.internal"))
      allow(Resolv).to receive(:getaddresses).and_return([ "169.254.169.254" ])
      expect(record).not_to be_valid
      expect(record.errors[:url]).to be_present
    end

    it "accepts a public IP" do
      record = RedashSource.new(valid_attributes)
      allow(Resolv).to receive(:getaddresses).and_return([ "203.0.113.10" ])
      expect(record).to be_valid
    end
  end

  describe "encryption (api_key)" do
    it "stores api_key encrypted (ciphertext in raw column)" do
      RedashSource.create!(valid_attributes)
      raw_value = ActiveRecord::Base.connection.select_value("SELECT api_key FROM redash_sources LIMIT 1")
      expect(raw_value).not_to eq("dummy_api_key_12345")
    end

    it "decrypts api_key transparently via the model accessor" do
      RedashSource.create!(valid_attributes)
      reloaded = RedashSource.first
      expect(reloaded.api_key).to eq("dummy_api_key_12345")
    end
  end
end
