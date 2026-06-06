require "rails_helper"

RSpec.describe OauthIdentity, type: :model do
  let(:user) { User.create!(email: "oid@example.com", password: "password", role: "member") }

  describe "associations" do
    it "belongs to a user" do
      expect(described_class.reflect_on_association(:user).macro).to eq(:belongs_to)
    end
  end

  describe "validations" do
    it "is valid with user, provider, uid" do
      identity = described_class.new(user: user, provider: "google_oauth2", uid: "1234567890")
      expect(identity).to be_valid
    end

    it "requires a provider" do
      identity = described_class.new(user: user, uid: "abc")
      expect(identity).not_to be_valid
      expect(identity.errors[:provider]).to be_present
    end

    it "requires a uid" do
      identity = described_class.new(user: user, provider: "google_oauth2")
      expect(identity).not_to be_valid
      expect(identity.errors[:uid]).to be_present
    end

    it "enforces (provider, uid) uniqueness" do
      described_class.create!(user: user, provider: "google_oauth2", uid: "dup")
      other = User.create!(email: "other@example.com", password: "password", role: "member")
      dup = described_class.new(user: other, provider: "google_oauth2", uid: "dup")
      expect(dup).not_to be_valid
      expect(dup.errors[:uid]).to be_present
    end

    it "allows the same uid on different providers" do
      described_class.create!(user: user, provider: "google_oauth2", uid: "shared")
      other = User.create!(email: "other2@example.com", password: "password", role: "member")
      identity = described_class.new(user: other, provider: "microsoft", uid: "shared")
      expect(identity).to be_valid
    end
  end

  describe ".for(provider, uid)" do
    it "scopes the relation by provider and uid" do
      identity = described_class.create!(user: user, provider: "google_oauth2", uid: "xyz")
      expect(described_class.for("google_oauth2", "xyz")).to include(identity)
      expect(described_class.for("google_oauth2", "other")).to be_empty
    end
  end
end
