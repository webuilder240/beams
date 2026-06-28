require "test_helper"

class ApplicationSettingTest < ActiveSupport::TestCase
  # --- .instance (singleton) ---
  test "creates the row on first access with the default rate" do
    before_count = ApplicationSetting.count
    assert_equal 950.0, ApplicationSetting.instance.bigquery_yen_per_tb
    assert_equal before_count + 1, ApplicationSetting.count
  end

  test "returns the same single row on subsequent access" do
    first = ApplicationSetting.instance
    second = ApplicationSetting.instance
    assert_equal first.id, second.id
    assert_equal 1, ApplicationSetting.count
  end

  # --- validations ---
  test "is valid with the default" do
    assert ApplicationSetting.new(bigquery_yen_per_tb: 950.0).valid?
  end

  test "allows zero" do
    assert ApplicationSetting.new(bigquery_yen_per_tb: 0).valid?
  end

  test "rejects a negative rate" do
    setting = ApplicationSetting.new(bigquery_yen_per_tb: -1)
    assert_not setting.valid?
    assert_predicate setting.errors[:bigquery_yen_per_tb], :present?
  end

  test "rejects a non-numeric rate" do
    setting = ApplicationSetting.new(bigquery_yen_per_tb: "abc")
    assert_not setting.valid?
    assert_predicate setting.errors[:bigquery_yen_per_tb], :present?
  end

  test "requires a rate (NOT NULL)" do
    setting = ApplicationSetting.new(bigquery_yen_per_tb: nil)
    assert_not setting.valid?
    assert_predicate setting.errors[:bigquery_yen_per_tb], :present?
  end
end
