require "rails_helper"

RSpec.describe Visualization, type: :model do
  describe "associations" do
    it { is_expected.to respond_to(:query) }

    it "belongs to a query" do
      query = create(:query)
      viz = create(:visualization, query: query)
      expect(viz.query).to eq(query)
    end

    it "is destroyed when its query is destroyed" do
      query = create(:query)
      create(:visualization, query: query)
      expect { query.destroy }.to change(Visualization, :count).by(-1)
    end

    it "enforces one visualization per query (has_one)" do
      query = create(:query)
      create(:visualization, query: query)
      dup = build(:visualization, query: query)
      expect(dup).not_to be_valid
    end
  end

  describe "validations" do
    it "accepts the allowed chart types" do
      %w[line bar pie area scatter counter].each do |type|
        expect(build(:visualization, chart_type: type)).to be_valid
      end
    end

    it "rejects an unknown chart type" do
      expect(build(:visualization, chart_type: "doughnut")).not_to be_valid
    end

    it "accepts the allowed display modes" do
      %w[table chart].each do |mode|
        expect(build(:visualization, display_mode: mode)).to be_valid
      end
    end

    it "rejects an unknown display mode" do
      expect(build(:visualization, display_mode: "grid")).not_to be_valid
    end

    it "accepts the allowed counter aggregations" do
      %w[sum avg count min max].each do |agg|
        expect(build(:visualization, counter_aggregation: agg)).to be_valid
      end
    end

    it "rejects an unknown counter aggregation" do
      expect(build(:visualization, counter_aggregation: "median")).not_to be_valid
    end
  end

  describe "y_columns serialization" do
    it "round-trips an array of strings" do
      viz = create(:visualization, y_columns: %w[col_a col_b])
      expect(viz.reload.y_columns).to eq(%w[col_a col_b])
    end

    it "defaults to nil when not set" do
      viz = create(:visualization)
      expect(viz.reload.y_columns).to be_nil
    end
  end

  describe "#counter_value" do
    let(:viz) { build(:visualization, chart_type: "counter", counter_column: "amount") }

    def execution_with(schema:, rows:)
      exec = build(:query_execution)
      exec.store_result(schema, rows)
      exec
    end

    let(:execution) do
      execution_with(
        schema: [ { "name" => "amount", "type" => "INTEGER" }, { "name" => "label", "type" => "STRING" } ],
        rows: [ [ 10, "a" ], [ 20, "b" ], [ 30, "c" ] ]
      )
    end

    it "computes the sum of the counter column" do
      viz.counter_aggregation = "sum"
      expect(viz.counter_value(execution)).to eq(60)
    end

    it "computes the average" do
      viz.counter_aggregation = "avg"
      expect(viz.counter_value(execution)).to eq(20)
    end

    it "computes the min" do
      viz.counter_aggregation = "min"
      expect(viz.counter_value(execution)).to eq(10)
    end

    it "computes the max" do
      viz.counter_aggregation = "max"
      expect(viz.counter_value(execution)).to eq(30)
    end

    it "counts the non-null values" do
      viz.counter_aggregation = "count"
      exec = execution_with(
        schema: [ { "name" => "amount", "type" => "INTEGER" } ],
        rows: [ [ 10 ], [ nil ], [ 30 ] ]
      )
      expect(viz.counter_value(exec)).to eq(2)
    end

    it "returns nil when the counter column is not set" do
      viz.counter_column = nil
      expect(viz.counter_value(execution)).to be_nil
    end

    it "returns nil when the column is not present in the schema" do
      viz.counter_column = "missing"
      expect(viz.counter_value(execution)).to be_nil
    end

    it "returns nil when the execution has no result" do
      expect(viz.counter_value(build(:query_execution))).to be_nil
    end

    it "treats non-numeric values as zero for sum (safe side)" do
      exec = execution_with(
        schema: [ { "name" => "amount", "type" => "STRING" } ],
        rows: [ [ "x" ], [ "y" ] ]
      )
      viz.counter_aggregation = "sum"
      expect(viz.counter_value(exec)).to eq(0)
    end

    it "returns nil for avg/min/max when there are no numeric values" do
      exec = execution_with(
        schema: [ { "name" => "amount", "type" => "STRING" } ],
        rows: [ [ "x" ], [ "y" ] ]
      )
      %w[avg min max].each do |agg|
        viz.counter_aggregation = agg
        expect(viz.counter_value(exec)).to be_nil
      end
    end
  end
end
