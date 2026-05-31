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

  describe "#ordered_widgets" do
    it "returns widgets ordered by position ascending" do
      dashboard = create(:dashboard)
      w3 = create(:widget, dashboard: dashboard, position: 3)
      w1 = create(:widget, dashboard: dashboard, position: 1)
      w2 = create(:widget, dashboard: dashboard, position: 2)

      expect(dashboard.ordered_widgets.to_a).to eq([ w1, w2, w3 ])
    end
  end
end
