require "rails_helper"

RSpec.describe User, type: :model do
  describe "factory" do
    it "builds a valid user" do
      expect(build(:user)).to be_valid
    end

    it "creates admin and member via traits" do
      expect(create(:user, :admin).role).to eq("admin")
      expect(create(:user, :member).role).to eq("member")
    end
  end

  describe "validations" do
    it "requires an email" do
      user = build(:user, email: nil)
      expect(user).not_to be_valid
      expect(user.errors[:email]).to be_present
    end

    it "requires a unique email (case-insensitive)" do
      create(:user, email: "dup@example.com")
      user = build(:user, email: "DUP@example.com")
      expect(user).not_to be_valid
      expect(user.errors[:email]).to be_present
    end

    it "rejects an invalid email format" do
      user = build(:user, email: "not-an-email")
      expect(user).not_to be_valid
      expect(user.errors[:email]).to be_present
    end

    it "requires a password on create" do
      user = User.new(email: "a@example.com", role: "member")
      expect(user).not_to be_valid
      expect(user.errors[:password]).to be_present
    end

    it "defaults role to member" do
      user = User.create!(email: "default@example.com", password: "password")
      expect(user.role).to eq("member")
    end

    it "rejects an invalid role" do
      user = build(:user, role: "superuser")
      expect(user).not_to be_valid
      expect(user.errors[:role]).to be_present
    end

    it "allows admin and member roles" do
      expect(build(:user, role: "admin")).to be_valid
      expect(build(:user, role: "member")).to be_valid
    end
  end

  describe "email normalization" do
    it "downcases and strips the email before saving" do
      user = create(:user, email: "  Mixed@Example.COM  ")
      expect(user.email).to eq("mixed@example.com")
    end
  end

  describe "#authenticate" do
    let(:user) { create(:user, password: "secret123") }

    it "returns the user for a correct password" do
      expect(user.authenticate("secret123")).to eq(user)
    end

    it "returns false for an incorrect password" do
      expect(user.authenticate("wrong")).to be_falsey
    end
  end

  describe ".find_or_create_for_oauth" do
    let(:provider) { "google_oauth2" }

    context "when an OauthIdentity already exists" do
      it "returns the linked user" do
        existing = create(:user, email: "linked@example.com")
        existing.oauth_identities.create!(provider: provider, uid: "uid-1")

        result = described_class.find_or_create_for_oauth(provider: provider, uid: "uid-1", email: "any@example.com")
        expect(result).to eq(existing)
        expect(existing.reload.oauth_identities.count).to eq(1)
      end
    end

    context "when a user with the same email exists (no identity yet)" do
      it "links a new oauth_identity to the existing user (B4-A)" do
        existing = create(:user, email: "user@example.com")

        result = described_class.find_or_create_for_oauth(provider: provider, uid: "uid-2", email: "user@example.com")
        expect(result).to eq(existing)
        expect(existing.reload.oauth_identities.pluck(:provider, :uid)).to eq([ [ provider, "uid-2" ] ])
      end

      it "normalizes the incoming email for matching" do
        existing = create(:user, email: "mixed@example.com")
        result = described_class.find_or_create_for_oauth(provider: provider, uid: "uid-mixed", email: "  MIXED@Example.COM  ")
        expect(result).to eq(existing)
      end
    end

    context "when no user exists and allowed_email_domain matches" do
      before do
        ApplicationSetting.instance.update!(allowed_email_domain: "example.com")
      end

      it "creates a new member user with the oauth identity (B5-B)" do
        expect {
          described_class.find_or_create_for_oauth(provider: provider, uid: "uid-3", email: "new@example.com")
        }.to change(described_class, :count).by(1)
         .and change(OauthIdentity, :count).by(1)

        user = described_class.find_by(email: "new@example.com")
        expect(user.role).to eq("member")
        expect(user.password_credential).to be_nil
        expect(user.oauth_identities.pluck(:provider, :uid)).to eq([ [ provider, "uid-3" ] ])
      end
    end

    context "when no user exists and allowed_email_domain does not match" do
      before do
        ApplicationSetting.instance.update!(allowed_email_domain: "example.com")
      end

      it "returns nil and creates nothing" do
        expect {
          result = described_class.find_or_create_for_oauth(provider: provider, uid: "uid-x", email: "other@notexample.com")
          expect(result).to be_nil
        }.not_to change(described_class, :count)
      end
    end

    context "when allowed_email_domain is blank" do
      it "returns nil for any unregistered email" do
        expect {
          result = described_class.find_or_create_for_oauth(provider: provider, uid: "uid-y", email: "anyone@anywhere.com")
          expect(result).to be_nil
        }.not_to change(described_class, :count)
      end
    end
  end

  describe "OAuth-only user behaviour" do
    it "cannot authenticate with a password (B9-A)" do
      ApplicationSetting.instance.update!(allowed_email_domain: "example.com")
      described_class.find_or_create_for_oauth(provider: "google_oauth2", uid: "uid-9", email: "oa@example.com")
      user = described_class.find_by(email: "oa@example.com")
      expect(user.authenticate("any-password")).to be(false)
    end
  end

  describe "role predicates" do
    it "#admin? is true for admins" do
      expect(build(:user, :admin).admin?).to be(true)
      expect(build(:user, :member).admin?).to be(false)
    end

    it "#member? is true for members" do
      expect(build(:user, :member).member?).to be(true)
      expect(build(:user, :admin).member?).to be(false)
    end
  end
end
