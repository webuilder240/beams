require "test_helper"

class QueryTest < ActiveSupport::TestCase
  # --- factory ---
  test "builds a valid query" do
    assert build_query.valid?
  end

  test "creates a persisted query" do
    assert_predicate create_query, :persisted?
  end

  # --- validations ---
  test "requires a title" do
    query = build_query(title: nil)
    assert_not query.valid?
    assert_predicate query.errors[:title], :present?
  end

  test "requires a non-blank title" do
    query = build_query(title: "  ")
    assert_not query.valid?
    assert_predicate query.errors[:title], :present?
  end

  test "requires a sql_body" do
    query = build_query(sql_body: nil)
    assert_not query.valid?
    assert_predicate query.errors[:sql_body], :present?
  end

  test "requires a non-blank sql_body" do
    query = build_query(sql_body: "  ")
    assert_not query.valid?
    assert_predicate query.errors[:sql_body], :present?
  end

  test "requires a user" do
    query = build_query(user: nil)
    assert_not query.valid?
    assert_predicate query.errors[:user], :present?
  end

  test "requires a bigquery_connection" do
    query = build_query(bigquery_connection: nil)
    assert_not query.valid?
    assert_predicate query.errors[:bigquery_connection], :present?
  end

  # --- associations ---
  test "belongs to a user" do
    user = create_user
    query = create_query(user: user)
    assert_equal user, query.user
  end

  test "belongs to a bigquery_connection (class Bigquery::Connection)" do
    connection = create_bigquery_connection
    query = create_query(bigquery_connection: connection)
    assert_equal connection, query.bigquery_connection
    assert_kind_of Bigquery::Connection, query.bigquery_connection
  end

  test "exposes user.queries" do
    user = create_user
    query = create_query(user: user)
    assert_includes user.queries, query
  end

  test "has many query_parameters and destroys them with the query" do
    query = create_query(sql_body: "SELECT {{ a }}")
    query.sync_parameters!
    assert_equal 1, query.query_parameters.count
    before = QueryParameter.count
    query.destroy
    assert_equal before - 1, QueryParameter.count
  end

  # --- .text_matching ---
  test "returns queries whose title contains the term (partial match)" do
    hit = create_query(title: "売上集計", sql_body: "SELECT 1")
    create_query(title: "ユーザー一覧", sql_body: "SELECT 2")

    assert_equal [ hit ], Query.text_matching("売上").to_a
  end

  test "returns queries whose sql_body contains the term (partial match)" do
    hit = create_query(title: "無題", sql_body: "SELECT user_id FROM events")
    create_query(title: "別件", sql_body: "SELECT name FROM products")

    assert_equal [ hit ], Query.text_matching("user_id").to_a
  end

  test "returns queries matching either title or sql_body without duplicates" do
    title_only = create_query(title: "売上集計", sql_body: "SELECT 1")
    sql_only = create_query(title: "無題", sql_body: "SELECT amount FROM 売上")
    create_query(title: "別件", sql_body: "SELECT id FROM products")

    assert_equal [ title_only, sql_only ].sort_by(&:id), Query.text_matching("売上").to_a.sort_by(&:id)
  end

  test "returns an empty relation when neither title nor sql_body matches" do
    create_query(title: "売上集計", sql_body: "SELECT 1")

    assert_empty Query.text_matching("該当なし")
  end

  test "returns all queries when the term is blank" do
    create_query(title: "A")
    create_query(title: "B")

    assert_equal Query.all.to_a.sort_by(&:id), Query.text_matching("").to_a.sort_by(&:id)
    assert_equal Query.all.to_a.sort_by(&:id), Query.text_matching(nil).to_a.sort_by(&:id)
  end

  test "escapes the LIKE wildcard % so it is treated literally" do
    literal = create_query(title: "100%達成", sql_body: "SELECT 1")
    create_query(title: "未達成", sql_body: "SELECT 1")

    assert_equal [ literal ], Query.text_matching("100%").to_a
  end

  test "escapes the LIKE wildcard _ so it is treated literally" do
    literal = create_query(title: "a_b 集計", sql_body: "SELECT 1")
    create_query(title: "axb 集計", sql_body: "SELECT 1")

    assert_equal [ literal ], Query.text_matching("a_b").to_a
  end

  test "escapes the LIKE escape character \\ so it is treated literally" do
    literal = create_query(title: "無題", sql_body: "path\\to\\file")
    create_query(title: "無題2", sql_body: "pathXtoXfile")

    assert_equal [ literal ], Query.text_matching("path\\to").to_a
  end

  # --- #parameters (parser) ---
  test "returns an empty array when there are no parameters" do
    assert_equal [], build_query(sql_body: "SELECT 1").parameters
  end

  test "parses a single untyped parameter as :string" do
    assert_equal [ { name: "user_id", type: :string } ], build_query(sql_body: "SELECT {{ user_id }}").parameters
  end

  test "parses a number-typed parameter" do
    assert_equal [ { name: "user_id", type: :number } ], build_query(sql_body: "SELECT {{ user_id:number }}").parameters
  end

  test "parses a date-typed parameter" do
    assert_equal [ { name: "d", type: :date } ], build_query(sql_body: "SELECT {{ d:date }}").parameters
  end

  test "parses a date_range-typed parameter" do
    assert_equal [ { name: "d", type: :date_range } ], build_query(sql_body: "SELECT {{ d:date_range }}").parameters
  end

  test "parses multiple parameters in order of appearance" do
    sql = "SELECT * FROM t WHERE id = {{ id:number }} AND created BETWEEN {{ c:date_range }}"
    assert_equal [
      { name: "id", type: :number },
      { name: "c", type: :date_range }
    ], build_query(sql_body: sql).parameters
  end

  test "normalizes a repeated parameter name to a single entry" do
    sql = "SELECT {{ x }} WHERE a = {{ x }}"
    assert_equal [ { name: "x", type: :string } ], build_query(sql_body: sql).parameters
  end

  test "keeps the first declared type when a name repeats with another type" do
    sql = "SELECT {{ x:number }} WHERE a = {{ x }}"
    assert_equal [ { name: "x", type: :number } ], build_query(sql_body: sql).parameters
  end

  test "falls back to :string for an unknown type annotation" do
    assert_equal [ { name: "x", type: :string } ], build_query(sql_body: "SELECT {{ x:unknown }}").parameters
  end

  test "tolerates missing whitespace inside the braces" do
    assert_equal [ { name: "user_id", type: :number } ], build_query(sql_body: "SELECT {{user_id:number}}").parameters
  end

  test "ignores malformed annotations that are not valid identifiers" do
    assert_equal [], build_query(sql_body: "SELECT {{ 123abc }}").parameters
  end

  test "returns [] for blank sql" do
    assert_equal [], build_query(sql_body: nil).parameters
  end

  # --- #bound_sql ---
  test "replaces {{ name }} with @name" do
    query = build_query(sql_body: "SELECT {{ user_id }}")
    assert_equal "SELECT @user_id", query.bound_sql
  end

  test "replaces a typed parameter with @name (dropping the type)" do
    query = build_query(sql_body: "SELECT * WHERE id = {{ user_id:number }}")
    assert_equal "SELECT * WHERE id = @user_id", query.bound_sql
  end

  test "replaces date_range with the bare @name (start/end expansion is left to the template)" do
    query = build_query(sql_body: "WHERE c BETWEEN {{ c:date_range }}")
    assert_equal "WHERE c BETWEEN @c", query.bound_sql
  end

  test "leaves sql without parameters untouched" do
    query = build_query(sql_body: "SELECT 1")
    assert_equal "SELECT 1", query.bound_sql
  end

  test "never produces literal interpolation of values (no string concatenation path)" do
    query = build_query(sql_body: "SELECT {{ x }}")
    result = query.bound_sql
    assert_includes result, "@x"
    assert_no_match(/'.*'/, result)
  end

  # --- #sync_parameters! (via after_save) ---
  test "creates query_parameters from the saved SQL" do
    connection = create_bigquery_connection
    user = create_user
    query = create_query(user: user, bigquery_connection: connection, sql_body: "SELECT {{ x }}")
    assert_equal [ "x" ], query.query_parameters.pluck(:name)
  end

  test "adds a new parameter when the SQL gains one" do
    connection = create_bigquery_connection
    user = create_user
    query = create_query(user: user, bigquery_connection: connection, sql_body: "SELECT {{ a }}")
    query.update!(sql_body: "SELECT {{ a }}, {{ b:number }}")
    assert_equal [ "a", "b" ], query.query_parameters.order(:id).pluck(:name)
    assert_equal "number", query.query_parameters.find_by(name: "b").param_type
  end

  test "removes a parameter when the SQL drops one" do
    connection = create_bigquery_connection
    user = create_user
    query = create_query(user: user, bigquery_connection: connection, sql_body: "SELECT {{ a }}, {{ b }}")
    query.update!(sql_body: "SELECT {{ a }}")
    assert_equal [ "a" ], query.query_parameters.pluck(:name)
  end

  test "updates a parameter's type when the annotation changes" do
    connection = create_bigquery_connection
    user = create_user
    query = create_query(user: user, bigquery_connection: connection, sql_body: "SELECT {{ a }}")
    assert_equal "string", query.query_parameters.find_by(name: "a").param_type
    query.update!(sql_body: "SELECT {{ a:date }}")
    assert_equal "date", query.query_parameters.find_by(name: "a").param_type
  end

  test "clears all parameters when the SQL no longer has any" do
    connection = create_bigquery_connection
    user = create_user
    query = create_query(user: user, bigquery_connection: connection, sql_body: "SELECT {{ a }}")
    query.update!(sql_body: "SELECT 1")
    assert_empty query.query_parameters
  end

  test "orders parameters by id (appearance order)" do
    connection = create_bigquery_connection
    user = create_user
    query = create_query(user: user, bigquery_connection: connection, sql_body: "SELECT {{ z }}, {{ a }}")
    assert_equal [ "z", "a" ], query.query_parameters.pluck(:name)
  end

  # --- #permit_parameter_values ---
  test "keeps only values for defined parameter names" do
    query = create_query(sql_body: "SELECT {{ a }}, {{ b }}")
    result = query.permit_parameter_values("a" => "1", "b" => "2", "evil" => "x")
    assert_equal({ "a" => "1", "b" => "2" }, result)
  end

  test "ignores unknown names entirely" do
    query = create_query(sql_body: "SELECT {{ a }}, {{ b }}")
    result = query.permit_parameter_values("evil" => "DROP")
    assert_equal({}, result)
  end

  test "returns {} for nil input" do
    query = create_query(sql_body: "SELECT {{ a }}, {{ b }}")
    assert_equal({}, query.permit_parameter_values(nil))
  end

  # --- #missing_parameter_values (all parameters required) ---
  test "is empty when all parameters have values" do
    query = create_query(sql_body: "SELECT {{ a }}, {{ b }}")
    assert_equal [], query.missing_parameter_values("a" => "1", "b" => "2")
  end

  test "lists a parameter whose value is blank" do
    query = create_query(sql_body: "SELECT {{ a }}, {{ b }}")
    assert_equal [ "b" ], query.missing_parameter_values("a" => "1", "b" => "")
  end

  test "lists a parameter that is entirely absent" do
    query = create_query(sql_body: "SELECT {{ a }}, {{ b }}")
    assert_equal [ "b" ], query.missing_parameter_values("a" => "1")
  end

  test "lists all parameters when nothing is provided" do
    query = create_query(sql_body: "SELECT {{ a }}, {{ b }}")
    assert_equal [ "a", "b" ].sort, query.missing_parameter_values({}).sort
  end

  test "treats a date_range as missing when start or end is blank" do
    range_query = create_query(sql_body: "WHERE c BETWEEN {{ c:date_range }}")
    assert_equal [ "c" ], range_query.missing_parameter_values("c" => { "start" => "2026-01-01", "end" => "" })
    assert_equal [], range_query.missing_parameter_values("c" => { "start" => "2026-01-01", "end" => "2026-01-31" })
  end

  # --- #query_executions ---
  test "has many executions destroyed with the query" do
    query = create_query
    create_query_execution(query: query)
    before = QueryExecution.count
    query.destroy
    assert_equal before - 1, QueryExecution.count
  end

  # --- #latest_succeeded_execution ---
  test "returns the most recent succeeded execution" do
    query = create_query
    create_succeeded_query_execution(query: query, created_at: 2.hours.ago)
    newest = create_succeeded_query_execution(query: query, created_at: 1.minute.ago)
    assert_equal newest, query.latest_succeeded_execution
  end

  test "ignores non-succeeded executions" do
    query = create_query
    create_running_query_execution(query: query)
    create_failed_query_execution(query: query)
    assert_nil query.latest_succeeded_execution
  end

  test "is scoped to the query" do
    query = create_query
    other = create_query
    create_succeeded_query_execution(query: other)
    assert_nil query.latest_succeeded_execution
  end
end
