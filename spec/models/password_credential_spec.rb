require "rails_helper"

RSpec.describe PasswordCredential, type: :model do
  let(:user) { User.create!(email: "pc1@example.com", password: "password", role: "member") }

  describe "associations" do
    it "belongs to a user" do
      expect(described_class.reflect_on_association(:user).macro).to eq(:belongs_to)
    end
  end

  describe "validations" do
    it "is valid with a user and a password (OAuth-created user has no PC by default)" do
      oauth_user = User.new(email: "v1@example.com", role: "member")
      oauth_user.skip_password_validation = true
      oauth_user.save!
      pc = described_class.new(user: oauth_user, password: "secret123")
      expect(pc).to be_valid
    end

    it "requires a user_id (NOT NULL)" do
      pc = described_class.new(password: "secret123")
      expect(pc).not_to be_valid
      expect(pc.errors[:user]).to be_present
    end

    it "rejects a duplicate user_id" do
      # 既存ユーザーには User.create! 経由ですでに 1 つ生成されている
      duplicate = described_class.new(user: user, password: "another")
      expect(duplicate).not_to be_valid
      expect(duplicate.errors[:user_id]).to be_present
    end
  end

  describe "has_secure_password" do
    it "stores a bcrypt digest, not plaintext" do
      expect(user.password_credential.password_digest).not_to eq("password")
      expect(user.password_credential.password_digest).to match(/\$2[aby]\$/)
    end

    it "authenticates with the correct password" do
      expect(user.password_credential.authenticate("password")).to eq(user.password_credential)
    end

    it "returns false for a wrong password" do
      expect(user.password_credential.authenticate("wrong")).to be(false)
    end
  end
end
