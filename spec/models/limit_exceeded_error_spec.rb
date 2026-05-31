require "rails_helper"

RSpec.describe LimitExceededError, type: :model do
  it "is a StandardError so controllers can rescue it" do
    expect(described_class.new).to be_a(StandardError)
  end

  it "carries a message" do
    expect(LimitExceededError.new("over the limit").message).to eq("over the limit")
  end
end
