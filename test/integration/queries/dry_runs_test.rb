# frozen_string_literal: true

require "test_helper"

class Queries::DryRunsTest < ActionDispatch::IntegrationTest
  setup do
    @user = create_user(role: "member", password: "password")
    @other_user = create_user(role: "member", password: "password")
    @connection = create_bigquery_connection(maximum_bytes_billed: nil)
    @query = create_query(user: @user, bigquery_connection: @connection)
  end

  def login_as(who, password: "password")
    post session_path, params: { email: who.email, password: password }
  end

  # DryRun PORO を可能な限り単純な方法で差し替え、BigQuery API を呼ばせない。
  # call は { bytes_processed: bytes } を返す。
  # DryRun.new の呼び出し履歴は @dry_run_new_calls に記録する。
  def with_stubbed_dry_run(bytes:, &block)
    fake = Object.new
    fake_call_count = 0
    fake.define_singleton_method(:call) { fake_call_count += 1; { bytes_processed: bytes } }
    fake.define_singleton_method(:call_count) { fake_call_count }
    @dry_run_new_calls = []
    calls_ref = @dry_run_new_calls
    DryRun.stub(:new, ->(*args) { calls_ref << args; fake }) do
      @last_dry_run_fake = fake
      block.call(fake)
    end
  end

  # --- access control ---
  test "redirects unauthenticated requests to login" do
    create_user # セットアップ誘導回避
    post query_dry_run_path(@query), params: { sql: "SELECT 1" }
    assert_redirected_to new_session_path
  end

  # --- as a logged-in user ---
  test "returns the estimate for the current user's query" do
    login_as(@user)
    with_stubbed_dry_run(bytes: 5_368_709_120) do
      post query_dry_run_path(@query), params: { sql: "SELECT 1" }, as: :json
    end

    assert_response :ok
    body = response.parsed_body
    assert_equal 5.0, body["gb"]
    assert_equal 4.75, body["yen"]
    assert_equal false, body["over_limit"]
    assert_nil body["error"]
  end

  test "uses the SQL from the request body, not the saved query body" do
    login_as(@user)
    fake = nil
    with_stubbed_dry_run(bytes: 100) do |f|
      fake = f
      post query_dry_run_path(@query), params: { sql: "SELECT live_edit" }, as: :json
    end

    # DryRun.new(@connection, "SELECT live_edit") で呼ばれていること
    assert_equal 1, @dry_run_new_calls.size
    args = @dry_run_new_calls.first
    assert_equal @connection, args[0]
    assert_equal "SELECT live_edit", args[1]
    # fake.call が呼ばれたこと
    assert_equal 1, fake.call_count
  end

  test "reports over_limit with the limit (GB) and an error message when exceeded" do
    login_as(@user)
    @connection.update!(maximum_bytes_billed: 1_000) # ~very small
    with_stubbed_dry_run(bytes: 5_368_709_120) do
      post query_dry_run_path(@query), params: { sql: "SELECT 1" }, as: :json
    end

    assert_response :ok
    body = response.parsed_body
    assert_equal true, body["over_limit"]
    assert_predicate body["error"], :present?
    assert_equal CostEstimate.bytes_to_gb(1_000), body["limit_gb"]
  end

  test "stays under limit when bytes are within maximum_bytes_billed" do
    login_as(@user)
    @connection.update!(maximum_bytes_billed: 10_000_000_000) # 10 GB
    with_stubbed_dry_run(bytes: 5_368_709_120) do
      post query_dry_run_path(@query), params: { sql: "SELECT 1" }, as: :json
    end

    assert_equal false, response.parsed_body["over_limit"]
  end

  test "returns a JSON error when BigQuery raises" do
    login_as(@user)
    fake = Object.new
    fake.define_singleton_method(:call) { raise Google::Cloud::Error.new("invalid query: syntax error") }
    DryRun.stub(:new, ->(*_args) { fake }) do
      post query_dry_run_path(@query), params: { sql: "SELECT bad" }, as: :json
    end

    assert_response :unprocessable_content
    body = response.parsed_body
    assert_includes body["error"], "syntax error"
    assert_equal false, body["over_limit"]
  end

  test "does not dry-run another user's query (404)" do
    login_as(@user)
    foreign = create_query(user: @other_user)

    post query_dry_run_path(foreign), params: { sql: "SELECT 1" }, as: :json

    assert_response :not_found
  end
end
