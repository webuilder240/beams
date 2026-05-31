require "rails_helper"

RSpec.describe QueryParameter, type: :model do
  describe "constants" do
    it "defines the four supported types" do
      expect(QueryParameter::SUPPORTED_TYPES).to eq(%i[string number date date_range])
    end
  end

  describe "associations" do
    it "belongs to a query" do
      query = create(:query)
      param = QueryParameter.create!(query: query, name: "x", param_type: "string")
      expect(param.query).to eq(query)
      expect(query.query_parameters).to include(param)
    end
  end

  describe "validations" do
    let(:query) { create(:query) }

    it "is valid with a name, param_type and query" do
      param = QueryParameter.new(query: query, name: "user_id", param_type: "number")
      expect(param).to be_valid
    end

    it "requires a name" do
      param = QueryParameter.new(query: query, name: nil, param_type: "string")
      expect(param).not_to be_valid
      expect(param.errors[:name]).to be_present
    end

    it "rejects a name with spaces" do
      param = QueryParameter.new(query: query, name: "user id", param_type: "string")
      expect(param).not_to be_valid
      expect(param.errors[:name]).to be_present
    end

    it "rejects a name with non-word characters" do
      param = QueryParameter.new(query: query, name: "user-id", param_type: "string")
      expect(param).not_to be_valid
      expect(param.errors[:name]).to be_present
    end

    it "accepts a name with underscores and digits" do
      param = QueryParameter.new(query: query, name: "user_id_2", param_type: "string")
      expect(param).to be_valid
    end

    it "rejects an unsupported param_type" do
      param = QueryParameter.new(query: query, name: "x", param_type: "boolean")
      expect(param).not_to be_valid
      expect(param.errors[:param_type]).to be_present
    end

    it "accepts each supported param_type" do
      %w[string number date date_range].each do |t|
        param = QueryParameter.new(query: query, name: "x", param_type: t)
        expect(param).to be_valid, "expected param_type=#{t} to be valid"
      end
    end

    it "enforces uniqueness of name within a query" do
      QueryParameter.create!(query: query, name: "dup", param_type: "string")
      duplicate = QueryParameter.new(query: query, name: "dup", param_type: "string")
      expect(duplicate).not_to be_valid
      expect(duplicate.errors[:name]).to be_present
    end

    it "allows the same name across different queries" do
      other = create(:query)
      QueryParameter.create!(query: query, name: "shared", param_type: "string")
      param = QueryParameter.new(query: other, name: "shared", param_type: "string")
      expect(param).to be_valid
    end
  end

  describe "#to_bigquery_param" do
    let(:query) { create(:query) }

    it "returns the raw string value for a string type" do
      param = QueryParameter.new(query: query, name: "x", param_type: "string")
      expect(param.to_bigquery_param("o'brien")).to eq("o'brien")
    end

    it "returns an Integer for a number value that is a whole number" do
      param = QueryParameter.new(query: query, name: "x", param_type: "number")
      result = param.to_bigquery_param("42")
      expect(result).to eq(42)
      expect(result).to be_a(Integer)
    end

    it "returns a Float for a number value with a decimal part" do
      param = QueryParameter.new(query: query, name: "x", param_type: "number")
      result = param.to_bigquery_param("3.5")
      expect(result).to eq(3.5)
      expect(result).to be_a(Float)
    end

    it "raises for a non-numeric value on a number type" do
      param = QueryParameter.new(query: query, name: "x", param_type: "number")
      expect { param.to_bigquery_param("abc") }.to raise_error(ArgumentError)
    end

    it "returns a Date for a date value" do
      param = QueryParameter.new(query: query, name: "x", param_type: "date")
      result = param.to_bigquery_param("2026-05-31")
      expect(result).to eq(Date.new(2026, 5, 31))
      expect(result).to be_a(Date)
    end

    it "raises for an invalid date value" do
      param = QueryParameter.new(query: query, name: "x", param_type: "date")
      expect { param.to_bigquery_param("not-a-date") }.to raise_error(ArgumentError)
    end

    it "expands a date_range into _start and _end Date params" do
      param = QueryParameter.new(query: query, name: "created_at", param_type: "date_range")
      result = param.to_bigquery_param({ "start" => "2026-01-01", "end" => "2026-01-31" })
      expect(result).to eq(
        "created_at_start" => Date.new(2026, 1, 1),
        "created_at_end" => Date.new(2026, 1, 31)
      )
    end

    it "raises for an invalid date inside a date_range" do
      param = QueryParameter.new(query: query, name: "c", param_type: "date_range")
      expect { param.to_bigquery_param({ "start" => "bad", "end" => "2026-01-31" }) }
        .to raise_error(ArgumentError)
    end
  end

  describe "#bigquery_param_names" do
    let(:query) { create(:query) }

    it "returns [name] for a scalar type" do
      param = QueryParameter.new(query: query, name: "x", param_type: "number")
      expect(param.bigquery_param_names).to eq([ "x" ])
    end

    it "returns the start/end names for a date_range" do
      param = QueryParameter.new(query: query, name: "c", param_type: "date_range")
      expect(param.bigquery_param_names).to eq([ "c_start", "c_end" ])
    end
  end
end
