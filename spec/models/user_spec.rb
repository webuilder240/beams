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
