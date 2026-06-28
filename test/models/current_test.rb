require "test_helper"

class CurrentTest < ActiveSupport::TestCase
  teardown do
    Current.reset
  end

  test "ActiveSupport::CurrentAttributes を継承している" do
    assert_includes Current.ancestors, ActiveSupport::CurrentAttributes
  end

  # --- .user ---
  test "User オブジェクトをセット/取得できる" do
    user = create_user
    Current.user = user
    assert_equal user, Current.user
  end

  test "未セットのときは nil を返す" do
    assert_nil Current.user
  end

  test "reset で nil に戻る" do
    Current.user = create_user
    Current.reset
    assert_nil Current.user
  end
end
