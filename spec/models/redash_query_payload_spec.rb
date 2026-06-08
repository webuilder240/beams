require "rails_helper"

RSpec.describe RedashQueryPayload, type: :model do
  def payload(overrides = {})
    described_class.new({
      "id" => 1,
      "name" => "Daily users",
      "query" => "SELECT 1",
      "options" => { "parameters" => [] }
    }.merge(overrides))
  end

  describe "#valid?" do
    it "is valid with name and query" do
      expect(payload).to be_valid
    end

    it "is invalid when name is missing" do
      record = payload("name" => "")
      expect(record).not_to be_valid
      expect(record.errors).to include(match(/name/i).or(match(/タイトル/)))
    end

    it "is invalid when query body is missing" do
      record = payload("query" => "")
      expect(record).not_to be_valid
      expect(record.errors).to include(match(/query/i).or(match(/SQL/i)))
    end
  end

  describe "#title and #sql_body" do
    it "exposes the Redash name as title" do
      expect(payload("name" => "Revenue").title).to eq("Revenue")
    end

    it "exposes the Redash query as sql_body" do
      sql = "SELECT count(*) FROM users WHERE created_at >= {{ start }}"
      expect(payload("query" => sql).sql_body).to eq(sql)
    end
  end

  describe "#parameters (B4 type mapping)" do
    def parameters_for(redash_params)
      payload("options" => { "parameters" => redash_params }).parameters
    end

    it "maps text -> string" do
      params = parameters_for([ { "name" => "kw", "type" => "text" } ])
      expect(params).to eq([ { name: "kw", type: :string } ])
    end

    it "maps number -> number" do
      params = parameters_for([ { "name" => "n", "type" => "number" } ])
      expect(params).to eq([ { name: "n", type: :number } ])
    end

    it "maps date -> date" do
      params = parameters_for([ { "name" => "d", "type" => "date" } ])
      expect(params).to eq([ { name: "d", type: :date } ])
    end

    it "maps date-range -> date_range" do
      params = parameters_for([ { "name" => "r", "type" => "date-range" } ])
      expect(params).to eq([ { name: "r", type: :date_range } ])
    end

    it "maps datetime-local -> string with warning" do
      record = payload("options" => { "parameters" => [ { "name" => "t", "type" => "datetime-local" } ] })
      expect(record.parameters).to eq([ { name: "t", type: :string } ])
      expect(record.warnings.join).to match(/datetime-local/)
    end

    it "maps datetime-with-seconds -> string with warning" do
      record = payload("options" => { "parameters" => [ { "name" => "t", "type" => "datetime-with-seconds" } ] })
      expect(record.parameters).to eq([ { name: "t", type: :string } ])
      expect(record.warnings.join).to match(/datetime-with-seconds/)
    end

    it "maps datetime-range -> date_range with warning" do
      record = payload("options" => { "parameters" => [ { "name" => "r", "type" => "datetime-range" } ] })
      expect(record.parameters).to eq([ { name: "r", type: :date_range } ])
      expect(record.warnings.join).to match(/datetime-range/)
    end

    it "maps datetime-range-with-seconds -> date_range with warning" do
      record = payload("options" => { "parameters" => [ { "name" => "r", "type" => "datetime-range-with-seconds" } ] })
      expect(record.parameters).to eq([ { name: "r", type: :date_range } ])
      expect(record.warnings.join).to match(/datetime-range-with-seconds/)
    end

    it "maps enum -> string with warning" do
      record = payload("options" => { "parameters" => [ { "name" => "e", "type" => "enum" } ] })
      expect(record.parameters).to eq([ { name: "e", type: :string } ])
      expect(record.warnings.join).to match(/enum/)
    end

    it "maps query (dynamic dropdown) -> string with warning" do
      record = payload("options" => { "parameters" => [ { "name" => "q", "type" => "query" } ] })
      expect(record.parameters).to eq([ { name: "q", type: :string } ])
      expect(record.warnings.join).to match(/query/)
    end

    it "maps unknown type -> string with warning" do
      record = payload("options" => { "parameters" => [ { "name" => "x", "type" => "fancy-future-type" } ] })
      expect(record.parameters).to eq([ { name: "x", type: :string } ])
      expect(record.warnings.join).to match(/fancy-future-type/)
    end

    it "handles missing parameters key gracefully" do
      record = described_class.new("name" => "t", "query" => "SELECT 1")
      expect(record.parameters).to eq([])
    end
  end

  describe "#warnings (B7 拡張記法検出)" do
    it "warns when SQL contains a Redash filter expression" do
      sql = "SELECT {{ \"foo\" | json_encode }} FROM t"
      record = payload("query" => sql)
      expect(record.warnings.join).to match(/フィルタ式|filter/i)
    end

    it "warns when SQL contains a {% if %} template tag" do
      sql = "SELECT 1 {% if x %} WHERE 1=1 {% endif %}"
      record = payload("query" => sql)
      expect(record.warnings.join).to match(/テンプレート|template/i)
    end

    it "does not warn for plain {{ name }} substitution" do
      sql = "SELECT * FROM t WHERE id = {{ id }}"
      record = payload("query" => sql)
      expect(record.warnings).to be_empty
    end
  end
end
