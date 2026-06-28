require "test_helper"

class LimitExceededErrorTest < ActiveSupport::TestCase
  test "is a StandardError so controllers can rescue it" do
    assert_kind_of StandardError, LimitExceededError.new
  end

  test "carries a message" do
    assert_equal "over the limit", LimitExceededError.new("over the limit").message
  end
end
