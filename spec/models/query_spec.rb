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

    it "has many query_parameters and destroys them with the query" do
      query = create(:query, sql_body: "SELECT {{ a }}")
      query.sync_parameters!
      expect(query.query_parameters.count).to eq(1)
      expect { query.destroy }.to change(QueryParameter, :count).by(-1)
    end
  end

  describe "#parameters (parser)" do
    def params_for(sql)
      build(:query, sql_body: sql).parameters
    end

    it "returns an empty array when there are no parameters" do
      expect(params_for("SELECT 1")).to eq([])
    end

    it "parses a single untyped parameter as :string" do
      expect(params_for("SELECT {{ user_id }}")).to eq([ { name: "user_id", type: :string } ])
    end

    it "parses a number-typed parameter" do
      expect(params_for("SELECT {{ user_id:number }}")).to eq([ { name: "user_id", type: :number } ])
    end

    it "parses a date-typed parameter" do
      expect(params_for("SELECT {{ d:date }}")).to eq([ { name: "d", type: :date } ])
    end

    it "parses a date_range-typed parameter" do
      expect(params_for("SELECT {{ d:date_range }}")).to eq([ { name: "d", type: :date_range } ])
    end

    it "parses multiple parameters in order of appearance" do
      sql = "SELECT * FROM t WHERE id = {{ id:number }} AND created BETWEEN {{ c:date_range }}"
      expect(params_for(sql)).to eq([
        { name: "id", type: :number },
        { name: "c", type: :date_range }
      ])
    end

    it "normalizes a repeated parameter name to a single entry" do
      sql = "SELECT {{ x }} WHERE a = {{ x }}"
      expect(params_for(sql)).to eq([ { name: "x", type: :string } ])
    end

    it "keeps the first declared type when a name repeats with another type" do
      sql = "SELECT {{ x:number }} WHERE a = {{ x }}"
      expect(params_for(sql)).to eq([ { name: "x", type: :number } ])
    end

    it "falls back to :string for an unknown type annotation" do
      expect(params_for("SELECT {{ x:unknown }}")).to eq([ { name: "x", type: :string } ])
    end

    it "tolerates missing whitespace inside the braces" do
      expect(params_for("SELECT {{user_id:number}}")).to eq([ { name: "user_id", type: :number } ])
    end

    it "ignores malformed annotations that are not valid identifiers" do
      expect(params_for("SELECT {{ 123abc }}")).to eq([])
    end

    it "returns [] for blank sql" do
      expect(build(:query, sql_body: nil).parameters).to eq([])
    end
  end

  describe "#bound_sql" do
    it "replaces {{ name }} with @name" do
      query = build(:query, sql_body: "SELECT {{ user_id }}")
      expect(query.bound_sql).to eq("SELECT @user_id")
    end

    it "replaces a typed parameter with @name (dropping the type)" do
      query = build(:query, sql_body: "SELECT * WHERE id = {{ user_id:number }}")
      expect(query.bound_sql).to eq("SELECT * WHERE id = @user_id")
    end

    it "replaces date_range with the bare @name (start/end expansion is left to the template)" do
      query = build(:query, sql_body: "WHERE c BETWEEN {{ c:date_range }}")
      expect(query.bound_sql).to eq("WHERE c BETWEEN @c")
    end

    it "leaves sql without parameters untouched" do
      query = build(:query, sql_body: "SELECT 1")
      expect(query.bound_sql).to eq("SELECT 1")
    end

    it "never produces literal interpolation of values (no string concatenation path)" do
      # bound_sql must only emit @name placeholders, never the value itself.
      query = build(:query, sql_body: "SELECT {{ x }}")
      result = query.bound_sql
      expect(result).to include("@x")
      expect(result).not_to match(/'.*'/) # no quoted literal injected
    end
  end

  describe "#sync_parameters! (via after_save)" do
    let(:connection) { create(:bigquery_connection) }
    let(:user) { create(:user) }

    it "creates query_parameters from the saved SQL" do
      query = create(:query, user: user, bigquery_connection: connection, sql_body: "SELECT {{ x }}")
      expect(query.query_parameters.pluck(:name)).to eq([ "x" ])
    end

    it "adds a new parameter when the SQL gains one" do
      query = create(:query, user: user, bigquery_connection: connection, sql_body: "SELECT {{ a }}")
      query.update!(sql_body: "SELECT {{ a }}, {{ b:number }}")
      expect(query.query_parameters.order(:id).pluck(:name)).to eq([ "a", "b" ])
      expect(query.query_parameters.find_by(name: "b").param_type).to eq("number")
    end

    it "removes a parameter when the SQL drops one" do
      query = create(:query, user: user, bigquery_connection: connection, sql_body: "SELECT {{ a }}, {{ b }}")
      query.update!(sql_body: "SELECT {{ a }}")
      expect(query.query_parameters.pluck(:name)).to eq([ "a" ])
    end

    it "updates a parameter's type when the annotation changes" do
      query = create(:query, user: user, bigquery_connection: connection, sql_body: "SELECT {{ a }}")
      expect(query.query_parameters.find_by(name: "a").param_type).to eq("string")
      query.update!(sql_body: "SELECT {{ a:date }}")
      expect(query.query_parameters.find_by(name: "a").param_type).to eq("date")
    end

    it "clears all parameters when the SQL no longer has any" do
      query = create(:query, user: user, bigquery_connection: connection, sql_body: "SELECT {{ a }}")
      query.update!(sql_body: "SELECT 1")
      expect(query.query_parameters).to be_empty
    end

    it "orders parameters by id (appearance order)" do
      query = create(:query, user: user, bigquery_connection: connection, sql_body: "SELECT {{ z }}, {{ a }}")
      expect(query.query_parameters.pluck(:name)).to eq([ "z", "a" ])
    end
  end

  describe "#permit_parameter_values" do
    let(:query) { create(:query, sql_body: "SELECT {{ a }}, {{ b }}") }

    it "keeps only values for defined parameter names" do
      result = query.permit_parameter_values("a" => "1", "b" => "2", "evil" => "x")
      expect(result).to eq("a" => "1", "b" => "2")
    end

    it "ignores unknown names entirely" do
      result = query.permit_parameter_values("evil" => "DROP")
      expect(result).to eq({})
    end

    it "returns {} for nil input" do
      expect(query.permit_parameter_values(nil)).to eq({})
    end
  end

  describe "#missing_parameter_values (all parameters required)" do
    let(:query) { create(:query, sql_body: "SELECT {{ a }}, {{ b }}") }

    it "is empty when all parameters have values" do
      expect(query.missing_parameter_values("a" => "1", "b" => "2")).to eq([])
    end

    it "lists a parameter whose value is blank" do
      expect(query.missing_parameter_values("a" => "1", "b" => "")).to eq([ "b" ])
    end

    it "lists a parameter that is entirely absent" do
      expect(query.missing_parameter_values("a" => "1")).to eq([ "b" ])
    end

    it "lists all parameters when nothing is provided" do
      expect(query.missing_parameter_values({})).to match_array([ "a", "b" ])
    end

    it "treats a date_range as missing when start or end is blank" do
      range_query = create(:query, sql_body: "WHERE c BETWEEN {{ c:date_range }}")
      expect(range_query.missing_parameter_values("c" => { "start" => "2026-01-01", "end" => "" })).to eq([ "c" ])
      expect(range_query.missing_parameter_values("c" => { "start" => "2026-01-01", "end" => "2026-01-31" })).to eq([])
    end
  end

  describe "#query_executions" do
    it "has many executions destroyed with the query" do
      query = create(:query)
      create(:query_execution, query: query)
      expect { query.destroy }.to change(QueryExecution, :count).by(-1)
    end
  end

  describe "#latest_succeeded_execution" do
    let(:query) { create(:query) }

    it "returns the most recent succeeded execution" do
      create(:query_execution, :succeeded, query: query, created_at: 2.hours.ago)
      newest = create(:query_execution, :succeeded, query: query, created_at: 1.minute.ago)
      expect(query.latest_succeeded_execution).to eq(newest)
    end

    it "ignores non-succeeded executions" do
      create(:query_execution, :running, query: query)
      create(:query_execution, :failed, query: query)
      expect(query.latest_succeeded_execution).to be_nil
    end

    it "is scoped to the query" do
      other = create(:query)
      create(:query_execution, :succeeded, query: other)
      expect(query.latest_succeeded_execution).to be_nil
    end
  end
end
