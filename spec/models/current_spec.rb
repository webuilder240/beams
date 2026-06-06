require "rails_helper"

RSpec.describe Current do
  it "ActiveSupport::CurrentAttributes を継承している" do
    expect(described_class.ancestors).to include(ActiveSupport::CurrentAttributes)
  end

  describe ".user" do
    after { described_class.reset }

    it "User オブジェクトをセット/取得できる" do
      user = create(:user)
      described_class.user = user
      expect(described_class.user).to eq(user)
    end

    it "未セットのときは nil を返す" do
      expect(described_class.user).to be_nil
    end

    it "reset で nil に戻る" do
      described_class.user = create(:user)
      described_class.reset
      expect(described_class.user).to be_nil
    end
  end
end
