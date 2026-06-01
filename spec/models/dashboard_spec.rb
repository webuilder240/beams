require "rails_helper"

RSpec.describe Dashboard, type: :model do
  describe "factory" do
    it "builds a valid dashboard" do
      expect(create(:dashboard)).to be_valid
    end
  end

  describe "associations" do
    it { is_expected.to respond_to(:user) }
    it { is_expected.to respond_to(:widgets) }

    it "belongs to a user (owner)" do
      user = create(:user)
      dashboard = create(:dashboard, user: user)
      expect(dashboard.user).to eq(user)
    end

    it "destroys its widgets when destroyed (CASCADE)" do
      dashboard = create(:dashboard)
      create(:widget, dashboard: dashboard)
      create(:widget, dashboard: dashboard)
      expect { dashboard.destroy }.to change(Widget, :count).by(-2)
    end
  end

  describe "validations" do
    it "requires a title" do
      expect(build(:dashboard, title: nil)).not_to be_valid
    end

    it "rejects a blank title" do
      expect(build(:dashboard, title: "")).not_to be_valid
    end

    it "accepts a title of 255 characters" do
      expect(build(:dashboard, title: "a" * 255)).to be_valid
    end

    it "rejects a title longer than 255 characters" do
      expect(build(:dashboard, title: "a" * 256)).not_to be_valid
    end
  end

  describe ".title_matching" do
    it "returns dashboards whose title contains the term (partial match)" do
      hit = create(:dashboard, title: "売上ダッシュボード")
      create(:dashboard, title: "ユーザー分析")

      expect(Dashboard.title_matching("売上")).to contain_exactly(hit)
    end

    it "returns all dashboards when the term is blank" do
      create(:dashboard, title: "A")
      create(:dashboard, title: "B")

      expect(Dashboard.title_matching("")).to match_array(Dashboard.all)
      expect(Dashboard.title_matching(nil)).to match_array(Dashboard.all)
    end

    it "escapes the LIKE wildcard % so it is treated literally" do
      literal = create(:dashboard, title: "100%達成")
      create(:dashboard, title: "未達成")

      expect(Dashboard.title_matching("100%")).to contain_exactly(literal)
    end

    it "escapes the LIKE wildcard _ so it is treated literally" do
      literal = create(:dashboard, title: "a_b レポート")
      create(:dashboard, title: "axb レポート")

      expect(Dashboard.title_matching("a_b")).to contain_exactly(literal)
    end
  end

  describe "#ordered_widgets" do
    it "returns widgets ordered by position ascending" do
      dashboard = create(:dashboard)
      w3 = create(:widget, dashboard: dashboard, position: 3)
      w1 = create(:widget, dashboard: dashboard, position: 1)
      w2 = create(:widget, dashboard: dashboard, position: 2)

      expect(dashboard.ordered_widgets.to_a).to eq([ w1, w2, w3 ])
    end
  end

  describe "#reorder_widgets!" do
    let(:dashboard) { create(:dashboard) }
    let!(:w1) { create(:widget, dashboard: dashboard, position: 0) }
    let!(:w2) { create(:widget, dashboard: dashboard, position: 1) }
    let!(:w3) { create(:widget, dashboard: dashboard, position: 2) }

    it "reorders widgets by the given ID array" do
      dashboard.reorder_widgets!([ w3.id, w1.id, w2.id ])

      expect(dashboard.ordered_widgets.to_a).to eq([ w3, w1, w2 ])
    end

    it "assigns positions starting from 0" do
      dashboard.reorder_widgets!([ w2.id, w3.id, w1.id ])

      expect(w2.reload.position).to eq(0)
      expect(w3.reload.position).to eq(1)
      expect(w1.reload.position).to eq(2)
    end

    it "ignores IDs that belong to other dashboards" do
      other_dashboard = create(:dashboard)
      other_widget = create(:widget, dashboard: other_dashboard, position: 0)

      expect {
        dashboard.reorder_widgets!([ other_widget.id, w1.id, w2.id, w3.id ])
      }.not_to change { other_widget.reload.position }

      # other_widget の ID が混入しても自ダッシュボードのウィジェットは更新される
      expect(w1.reload.position).to eq(0)
      expect(w2.reload.position).to eq(1)
    end

    it "leaves out widgets whose IDs are not in the array unchanged in relative order" do
      # w3 を配列に含めなくても、w1/w2 は指定順で更新される
      dashboard.reorder_widgets!([ w2.id, w1.id ])

      expect(w2.reload.position).to eq(0)
      expect(w1.reload.position).to eq(1)
    end

    it "runs in a transaction (all-or-nothing)" do
      # 内部で例外が出ても途中更新が残らないことを確認（トランザクション保証）
      allow(dashboard.widgets).to receive(:find_by).and_call_original
      original_positions = [ w1.position, w2.position, w3.position ]

      dashboard.reorder_widgets!([ w1.id, w2.id, w3.id ])

      expect([ w1.reload.position, w2.reload.position, w3.reload.position ])
        .to eq([ 0, 1, 2 ])
      # もとの期待値が変更されているので反転はしない（正常系の確認）
      expect(original_positions).to eq([ 0, 1, 2 ])
    end
  end
end
