require "test_helper"

class UserTest < ActiveSupport::TestCase
  # --- factory ---
  test "builds a valid user" do
    assert build_user.valid?
  end

  test "creates admin and member via traits" do
    assert_equal "admin", create_user(role: "admin").role
    assert_equal "member", create_user(role: "member").role
  end

  # --- validations ---
  test "requires an email" do
    user = build_user(email: nil)
    assert_not user.valid?
    assert_predicate user.errors[:email], :present?
  end

  test "requires a unique email (case-insensitive)" do
    create_user(email: "dup@example.com")
    user = build_user(email: "DUP@example.com")
    assert_not user.valid?
    assert_predicate user.errors[:email], :present?
  end

  test "rejects an invalid email format" do
    user = build_user(email: "not-an-email")
    assert_not user.valid?
    assert_predicate user.errors[:email], :present?
  end

  test "requires a password on create" do
    user = User.new(email: "a@example.com", role: "member")
    assert_not user.valid?
    assert_predicate user.errors[:password], :present?
  end

  test "defaults role to member" do
    user = User.create!(email: "default@example.com", password: "password")
    assert_equal "member", user.role
  end

  test "rejects an invalid role" do
    user = build_user(role: "superuser")
    assert_not user.valid?
    assert_predicate user.errors[:role], :present?
  end

  test "allows admin and member roles" do
    assert build_user(role: "admin").valid?
    assert build_user(role: "member").valid?
  end

  # --- email normalization ---
  test "downcases and strips the email before saving" do
    user = create_user(email: "  Mixed@Example.COM  ")
    assert_equal "mixed@example.com", user.email
  end

  # --- #authenticate ---
  test "#authenticate returns the user for a correct password" do
    user = create_user(password: "secret123")
    assert_equal user, user.authenticate("secret123")
  end

  test "#authenticate returns false for an incorrect password" do
    user = create_user(password: "secret123")
    assert_not user.authenticate("wrong")
  end

  # --- role predicates ---
  test "#admin? is true for admins" do
    assert build_user(role: "admin").admin?
    assert_not build_user(role: "member").admin?
  end

  test "#member? is true for members" do
    assert build_user(role: "member").member?
    assert_not build_user(role: "admin").member?
  end
end
