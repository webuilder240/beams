require "application_system_test_case"

class HealthCheckTest < ApplicationSystemTestCase
  test "returns 200 on /up" do
    visit "/up"
    assert_equal 200, page.status_code
  end
end
