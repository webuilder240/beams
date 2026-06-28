require "test_helper"

class DashboardTest < ActiveSupport::TestCase
  # --- factory ---
  test "builds a valid dashboard" do
    assert create_dashboard.valid?
  end

  # --- associations ---
  test "responds to user" do
    assert_respond_to Dashboard.new, :user
  end

  test "responds to widgets" do
    assert_respond_to Dashboard.new, :widgets
  end

  test "belongs to a user (owner)" do
    user = create_user
    dashboard = create_dashboard(user: user)
    assert_equal user, dashboard.user
  end

  test "destroys its widgets when destroyed (CASCADE)" do
    dashboard = create_dashboard
    create_widget(dashboard: dashboard)
    create_widget(dashboard: dashboard)
    before = Widget.count
    dashboard.destroy
    assert_equal before - 2, Widget.count
  end

  # --- validations ---
  test "requires a title" do
    assert_not build_dashboard(title: nil).valid?
  end

  test "rejects a blank title" do
    assert_not build_dashboard(title: "").valid?
  end

  test "accepts a title of 255 characters" do
    assert build_dashboard(title: "a" * 255).valid?
  end

  test "rejects a title longer than 255 characters" do
    assert_not build_dashboard(title: "a" * 256).valid?
  end

  # --- .title_matching ---
  test "returns dashboards whose title contains the term (partial match)" do
    hit = create_dashboard(title: "売上ダッシュボード")
    create_dashboard(title: "ユーザー分析")

    assert_equal [ hit ], Dashboard.title_matching("売上").to_a
  end

  test "returns all dashboards when the term is blank" do
    create_dashboard(title: "A")
    create_dashboard(title: "B")

    assert_equal Dashboard.all.to_a.sort_by(&:id), Dashboard.title_matching("").to_a.sort_by(&:id)
    assert_equal Dashboard.all.to_a.sort_by(&:id), Dashboard.title_matching(nil).to_a.sort_by(&:id)
  end

  test "escapes the LIKE wildcard % so it is treated literally" do
    literal = create_dashboard(title: "100%達成")
    create_dashboard(title: "未達成")

    assert_equal [ literal ], Dashboard.title_matching("100%").to_a
  end

  test "escapes the LIKE wildcard _ so it is treated literally" do
    literal = create_dashboard(title: "a_b レポート")
    create_dashboard(title: "axb レポート")

    assert_equal [ literal ], Dashboard.title_matching("a_b").to_a
  end

  # --- #ordered_widgets ---
  test "returns widgets ordered by position ascending" do
    dashboard = create_dashboard
    w3 = create_widget(dashboard: dashboard, position: 3)
    w1 = create_widget(dashboard: dashboard, position: 1)
    w2 = create_widget(dashboard: dashboard, position: 2)

    assert_equal [ w1, w2, w3 ], dashboard.ordered_widgets.to_a
  end

  # --- #reorder_widgets! ---
  test "reorders widgets by the given ID array" do
    dashboard = create_dashboard
    w1 = create_widget(dashboard: dashboard, position: 0)
    w2 = create_widget(dashboard: dashboard, position: 1)
    w3 = create_widget(dashboard: dashboard, position: 2)

    dashboard.reorder_widgets!([ w3.id, w1.id, w2.id ])

    assert_equal [ w3, w1, w2 ], dashboard.ordered_widgets.to_a
  end

  test "assigns positions starting from 0" do
    dashboard = create_dashboard
    w1 = create_widget(dashboard: dashboard, position: 0)
    w2 = create_widget(dashboard: dashboard, position: 1)
    w3 = create_widget(dashboard: dashboard, position: 2)

    dashboard.reorder_widgets!([ w2.id, w3.id, w1.id ])

    assert_equal 0, w2.reload.position
    assert_equal 1, w3.reload.position
    assert_equal 2, w1.reload.position
  end

  test "ignores IDs that belong to other dashboards" do
    dashboard = create_dashboard
    w1 = create_widget(dashboard: dashboard, position: 0)
    w2 = create_widget(dashboard: dashboard, position: 1)
    w3 = create_widget(dashboard: dashboard, position: 2)

    other_dashboard = create_dashboard
    other_widget = create_widget(dashboard: other_dashboard, position: 0)

    original_other_position = other_widget.reload.position
    dashboard.reorder_widgets!([ other_widget.id, w1.id, w2.id, w3.id ])
    assert_equal original_other_position, other_widget.reload.position

    # other_widget の ID が混入しても自ダッシュボードのウィジェットは更新される
    assert_equal 0, w1.reload.position
    assert_equal 1, w2.reload.position
  end

  test "leaves out widgets whose IDs are not in the array unchanged in relative order" do
    dashboard = create_dashboard
    w1 = create_widget(dashboard: dashboard, position: 0)
    w2 = create_widget(dashboard: dashboard, position: 1)
    create_widget(dashboard: dashboard, position: 2)

    # w3 を配列に含めなくても、w1/w2 は指定順で更新される
    dashboard.reorder_widgets!([ w2.id, w1.id ])

    assert_equal 0, w2.reload.position
    assert_equal 1, w1.reload.position
  end

  test "rolls back all position updates when an error occurs mid-transaction" do
    dashboard = create_dashboard
    w1 = create_widget(dashboard: dashboard, position: 0)
    w2 = create_widget(dashboard: dashboard, position: 1)
    w3 = create_widget(dashboard: dashboard, position: 2)

    # 並び替え後と確実に異なる初期値にしておき、ロールバック後に元の値へ戻ることを検証する。
    w1.update!(position: 10)
    w2.update!(position: 20)
    w3.update!(position: 30)

    # transaction ブロック内の UPDATE 直後に ActiveRecord::Rollback を起こし、
    # コミットを妨げる（ActiveRecord の transaction はブロック内例外でロールバックする）。
    dashboard.define_singleton_method(:transaction) do |*_args, &block|
      ActiveRecord::Base.transaction do
        block.call
        raise ActiveRecord::Rollback, "forced rollback for test"
      end
    end

    dashboard.reorder_widgets!([ w3.id, w1.id, w2.id ])

    # ロールバックされ、全 position が元の値のまま（並び替えは反映されない）。
    assert_equal 10, w1.reload.position
    assert_equal 20, w2.reload.position
    assert_equal 30, w3.reload.position
  end
end
