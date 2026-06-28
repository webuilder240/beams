require "test_helper"

class QueryParameterTest < ActiveSupport::TestCase
  # --- constants ---
  test "defines the four supported types" do
    assert_equal %i[string number date date_range], QueryParameter::SUPPORTED_TYPES
  end

  # --- associations ---
  test "belongs to a query" do
    query = create_query
    param = QueryParameter.create!(query: query, name: "x", param_type: "string")
    assert_equal query, param.query
    assert_includes query.query_parameters, param
  end

  # --- validations ---
  test "is valid with a name, param_type and query" do
    query = create_query
    param = QueryParameter.new(query: query, name: "user_id", param_type: "number")
    assert param.valid?
  end

  test "requires a name" do
    query = create_query
    param = QueryParameter.new(query: query, name: nil, param_type: "string")
    assert_not param.valid?
    assert_predicate param.errors[:name], :present?
  end

  test "rejects a name with spaces" do
    query = create_query
    param = QueryParameter.new(query: query, name: "user id", param_type: "string")
    assert_not param.valid?
    assert_predicate param.errors[:name], :present?
  end

  test "rejects a name with non-word characters" do
    query = create_query
    param = QueryParameter.new(query: query, name: "user-id", param_type: "string")
    assert_not param.valid?
    assert_predicate param.errors[:name], :present?
  end

  test "accepts a name with underscores and digits" do
    query = create_query
    param = QueryParameter.new(query: query, name: "user_id_2", param_type: "string")
    assert param.valid?
  end

  test "rejects an unsupported param_type" do
    query = create_query
    param = QueryParameter.new(query: query, name: "x", param_type: "boolean")
    assert_not param.valid?
    assert_predicate param.errors[:param_type], :present?
  end

  test "accepts each supported param_type" do
    query = create_query
    %w[string number date date_range].each do |t|
      param = QueryParameter.new(query: query, name: "x", param_type: t)
      assert param.valid?, "expected param_type=#{t} to be valid"
    end
  end

  test "enforces uniqueness of name within a query" do
    query = create_query
    QueryParameter.create!(query: query, name: "dup", param_type: "string")
    duplicate = QueryParameter.new(query: query, name: "dup", param_type: "string")
    assert_not duplicate.valid?
    assert_predicate duplicate.errors[:name], :present?
  end

  test "allows the same name across different queries" do
    query = create_query
    other = create_query
    QueryParameter.create!(query: query, name: "shared", param_type: "string")
    param = QueryParameter.new(query: other, name: "shared", param_type: "string")
    assert param.valid?
  end

  # --- #to_bigquery_param ---
  test "returns the raw string value for a string type" do
    query = create_query
    param = QueryParameter.new(query: query, name: "x", param_type: "string")
    assert_equal "o'brien", param.to_bigquery_param("o'brien")
  end

  test "returns an Integer for a number value that is a whole number" do
    query = create_query
    param = QueryParameter.new(query: query, name: "x", param_type: "number")
    result = param.to_bigquery_param("42")
    assert_equal 42, result
    assert_kind_of Integer, result
  end

  test "returns a Float for a number value with a decimal part" do
    query = create_query
    param = QueryParameter.new(query: query, name: "x", param_type: "number")
    result = param.to_bigquery_param("3.5")
    assert_equal 3.5, result
    assert_kind_of Float, result
  end

  test "raises for a non-numeric value on a number type" do
    query = create_query
    param = QueryParameter.new(query: query, name: "x", param_type: "number")
    assert_raises(ArgumentError) { param.to_bigquery_param("abc") }
  end

  test "returns a Date for a date value" do
    query = create_query
    param = QueryParameter.new(query: query, name: "x", param_type: "date")
    result = param.to_bigquery_param("2026-05-31")
    assert_equal Date.new(2026, 5, 31), result
    assert_kind_of Date, result
  end

  test "raises for an invalid date value" do
    query = create_query
    param = QueryParameter.new(query: query, name: "x", param_type: "date")
    assert_raises(ArgumentError) { param.to_bigquery_param("not-a-date") }
  end

  test "expands a date_range into _start and _end Date params" do
    query = create_query
    param = QueryParameter.new(query: query, name: "created_at", param_type: "date_range")
    result = param.to_bigquery_param({ "start" => "2026-01-01", "end" => "2026-01-31" })
    assert_equal(
      {
        "created_at_start" => Date.new(2026, 1, 1),
        "created_at_end" => Date.new(2026, 1, 31)
      },
      result
    )
  end

  test "raises for an invalid date inside a date_range" do
    query = create_query
    param = QueryParameter.new(query: query, name: "c", param_type: "date_range")
    assert_raises(ArgumentError) do
      param.to_bigquery_param({ "start" => "bad", "end" => "2026-01-31" })
    end
  end

  # --- #bigquery_param_names ---
  test "returns [name] for a scalar type" do
    query = create_query
    param = QueryParameter.new(query: query, name: "x", param_type: "number")
    assert_equal [ "x" ], param.bigquery_param_names
  end

  test "returns the start/end names for a date_range" do
    query = create_query
    param = QueryParameter.new(query: query, name: "c", param_type: "date_range")
    assert_equal [ "c_start", "c_end" ], param.bigquery_param_names
  end
end
