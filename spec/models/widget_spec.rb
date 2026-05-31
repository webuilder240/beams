require "rails_helper"

RSpec.describe Widget, type: :model do
  describe "factory" do
    it "builds a valid widget" do
      expect(create(:widget)).to be_valid
    end
  end

  describe "associations" do
    it { is_expected.to respond_to(:dashboard) }
    it { is_expected.to respond_to(:query) }

    it "belongs to a dashboard" do
      dashboard = create(:dashboard)
      widget = create(:widget, dashboard: dashboard)
      expect(widget.dashboard).to eq(dashboard)
    end

    it "belongs to a query" do
      query = create(:query)
      widget = create(:widget, query: query)
      expect(widget.query).to eq(query)
    end
  end

  describe "validations" do
    it "rejects a negative position" do
      expect(build(:widget, position: -1)).not_to be_valid
    end

    it "rejects a non-integer position" do
      expect(build(:widget, position: 1.5)).not_to be_valid
    end

    it "accepts a position of 0" do
      expect(build(:widget, position: 0)).to be_valid
    end

    it "accepts column_span of 1 and 2" do
      expect(build(:widget, column_span: 1)).to be_valid
      expect(build(:widget, column_span: 2)).to be_valid
    end

    it "rejects column_span of 3" do
      expect(build(:widget, column_span: 3)).not_to be_valid
    end

    it "rejects column_span of 0" do
      expect(build(:widget, column_span: 0)).not_to be_valid
    end
  end

  describe "#display_title" do
    it "returns query.title when title_override is nil" do
      query = create(:query, title: "売上クエリ")
      widget = build(:widget, query: query, title_override: nil)
      expect(widget.display_title).to eq("売上クエリ")
    end

    it "returns query.title when title_override is blank" do
      query = create(:query, title: "売上クエリ")
      widget = build(:widget, query: query, title_override: "")
      expect(widget.display_title).to eq("売上クエリ")
    end

    it "returns title_override when present" do
      widget = build(:widget, title_override: "カスタム名")
      expect(widget.display_title).to eq("カスタム名")
    end
  end

  describe "reordering" do
    let(:dashboard) { create(:dashboard) }
    let!(:w1) { create(:widget, dashboard: dashboard, position: 0) }
    let!(:w2) { create(:widget, dashboard: dashboard, position: 1) }
    let!(:w3) { create(:widget, dashboard: dashboard, position: 2) }

    describe "#move_up!" do
      it "swaps position with the previous widget" do
        w2.move_up!
        expect(w1.reload.position).to eq(1)
        expect(w2.reload.position).to eq(0)
      end

      it "does nothing for the first widget (no-op)" do
        expect { w1.move_up! }.not_to(change { dashboard.ordered_widgets.pluck(:id) })
      end

      it "keeps ordering consistent after moving up" do
        w3.move_up!
        expect(dashboard.ordered_widgets.to_a).to eq([ w1, w3, w2 ])
      end
    end

    describe "#move_down!" do
      it "swaps position with the next widget" do
        w2.move_down!
        expect(w3.reload.position).to eq(1)
        expect(w2.reload.position).to eq(2)
      end

      it "does nothing for the last widget (no-op)" do
        expect { w3.move_down! }.not_to(change { dashboard.ordered_widgets.pluck(:id) })
      end

      it "keeps ordering consistent after moving down" do
        w1.move_down!
        expect(dashboard.ordered_widgets.to_a).to eq([ w2, w1, w3 ])
      end
    end
  end
end
