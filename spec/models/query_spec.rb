require "rails_helper"

RSpec.describe Query, type: :model do
  describe "factory" do
    it "builds a valid query" do
      expect(build(:query)).to be_valid
    end

    it "creates a persisted query" do
      expect(create(:query)).to be_persisted
    end
  end

  describe "validations" do
    it "requires a title" do
      query = build(:query, title: nil)
      expect(query).not_to be_valid
      expect(query.errors[:title]).to be_present
    end

    it "requires a non-blank title" do
      query = build(:query, title: "  ")
      expect(query).not_to be_valid
      expect(query.errors[:title]).to be_present
    end

    it "requires a sql_body" do
      query = build(:query, sql_body: nil)
      expect(query).not_to be_valid
      expect(query.errors[:sql_body]).to be_present
    end

    it "requires a non-blank sql_body" do
      query = build(:query, sql_body: "  ")
      expect(query).not_to be_valid
      expect(query.errors[:sql_body]).to be_present
    end

    it "requires a user" do
      query = build(:query, user: nil)
      expect(query).not_to be_valid
      expect(query.errors[:user]).to be_present
    end

    it "requires a bigquery_connection" do
      query = build(:query, bigquery_connection: nil)
      expect(query).not_to be_valid
      expect(query.errors[:bigquery_connection]).to be_present
    end
  end

  describe "associations" do
    it "belongs to a user" do
      user = create(:user)
      query = create(:query, user: user)
      expect(query.user).to eq(user)
    end

    it "belongs to a bigquery_connection (class Bigquery::Connection)" do
      connection = create(:bigquery_connection)
      query = create(:query, bigquery_connection: connection)
      expect(query.bigquery_connection).to eq(connection)
      expect(query.bigquery_connection).to be_a(Bigquery::Connection)
    end

    it "exposes user.queries" do
      user = create(:user)
      query = create(:query, user: user)
      expect(user.queries).to include(query)
    end
  end
end
