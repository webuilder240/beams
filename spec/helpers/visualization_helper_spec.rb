require "rails_helper"

RSpec.describe VisualizationHelper, type: :helper do
  def execution_with(schema:, rows:)
    exec = build(:query_execution)
    exec.store_result(schema, rows)
    exec
  end

  let(:execution) do
    execution_with(
      schema: [
        { "name" => "day", "type" => "STRING" },
        { "name" => "sales", "type" => "INTEGER" },
        { "name" => "cost", "type" => "INTEGER" }
      ],
      rows: [ [ "Mon", 10, 4 ], [ "Tue", 20, 8 ], [ "Wed", 30, 12 ] ]
    )
  end

  describe "#chart_config_for" do
    it "returns a hash with type and data for a line chart" do
      viz = build(:visualization, chart_type: "line", x_column: "day", y_columns: %w[sales])
      config = helper.chart_config_for(viz, execution)

      expect(config[:type]).to eq("line")
      expect(config[:data][:labels]).to eq(%w[Mon Tue Wed])
      expect(config[:data][:datasets].first[:label]).to eq("sales")
      expect(config[:data][:datasets].first[:data]).to eq([ 10, 20, 30 ])
    end

    it "supports multiple y columns" do
      viz = build(:visualization, chart_type: "bar", x_column: "day", y_columns: %w[sales cost])
      config = helper.chart_config_for(viz, execution)

      expect(config[:type]).to eq("bar")
      expect(config[:data][:datasets].size).to eq(2)
      expect(config[:data][:datasets].map { |d| d[:label] }).to eq(%w[sales cost])
    end

    it "maps area to a filled line chart" do
      viz = build(:visualization, chart_type: "area", x_column: "day", y_columns: %w[sales])
      config = helper.chart_config_for(viz, execution)

      expect(config[:type]).to eq("line")
      expect(config[:data][:datasets].first[:fill]).to be(true)
    end

    it "returns nil when the execution has no result" do
      viz = build(:visualization, chart_type: "line", x_column: "day", y_columns: %w[sales])
      expect(helper.chart_config_for(viz, build(:query_execution))).to be_nil
    end

    it "returns nil when axes are not configured" do
      viz = build(:visualization, chart_type: "line", x_column: nil, y_columns: nil)
      expect(helper.chart_config_for(viz, execution)).to be_nil
    end

    it "builds scatter data as {x, y} points using the first y column" do
      viz = build(:visualization, chart_type: "scatter", x_column: "sales", y_columns: %w[cost])
      config = helper.chart_config_for(viz, execution)

      expect(config[:type]).to eq("scatter")
      expect(config[:data][:datasets].first[:data]).to eq(
        [ { x: 10, y: 4 }, { x: 20, y: 8 }, { x: 30, y: 12 } ]
      )
    end
  end

  describe "#result_columns" do
    it "returns the column names from the execution result" do
      expect(helper.result_columns(execution)).to eq(%w[day sales cost])
    end

    it "returns an empty array when there is no result" do
      expect(helper.result_columns(build(:query_execution))).to eq([])
    end
  end
end
