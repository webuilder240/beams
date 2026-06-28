require "test_helper"

class Queries::Executions::CsvExportsTest < ActionDispatch::IntegrationTest
  def user
    @user ||= create_user(role: "member", password: "password")
  end

  def other_user
    @other_user ||= create_user(role: "member", password: "password")
  end

  def connection
    @connection ||= create_bigquery_connection
  end

  def query
    @query ||= create_query(user: user, bigquery_connection: connection)
  end

  def login_as(who, password: "password")
    post session_path, params: { email: who.email, password: password }
  end

  # Thruster（本番）が付与する X-Sendfile-Type を模した GET。
  # これにより Rack::Sendfile が応答に X-Sendfile ヘッダーを立てる。
  def get_csv(path_helper)
    get path_helper, headers: { "X-Sendfile-Type" => "X-Sendfile" }
  end

  # ジョブが書き出すはずの全件 CSV(.gz) をテスト用に用意する。
  def csv_dir
    Pathname.new(ENV.fetch("BEAMS_CSV_PATH") { Rails.root.join("storage/csv").to_s })
  end

  def write_csv_for(execution)
    FileUtils.mkdir_p(csv_dir)
    path = csv_dir.join("#{execution.id}.csv.gz")
    Zlib::GzipWriter.open(path) { |gz| gz.write("n\n1\n2\n") }
    path
  end

  teardown do
    # 自分が書いたファイルだけ消す（worker 共有 dir なので全削除はしない）。
    Dir.glob(csv_dir.join("*.csv.gz")).each { |f| File.delete(f) }
  end

  # --- access control ---
  test "redirects unauthenticated requests to login" do
    create_user
    get_csv latest_csv_query_executions_path(query)
    assert_redirected_to new_session_path
  end

  test "returns 404 for another user's query" do
    login_as(user)
    foreign = create_query(user: other_user, bigquery_connection: connection)
    get latest_csv_query_executions_path(foreign)
    assert_response :not_found
  end

  # --- as the owner ---
  test "sends the latest succeeded execution's CSV via X-Sendfile" do
    login_as(user)
    execution = create_succeeded_query_execution(query: query)
    path = write_csv_for(execution)

    get_csv latest_csv_query_executions_path(query)

    assert_response :ok
    assert_includes response.headers["Content-Type"], "text/csv"
    assert_equal path.to_s, response.headers["X-Sendfile"]
  end

  test "serves the full CSV even when the displayed result was truncated" do
    login_as(user)
    execution = create_succeeded_query_execution(query: query, result_truncated: true)
    path = write_csv_for(execution)

    get_csv latest_csv_query_executions_path(query)

    assert_response :ok
    assert_equal path.to_s, response.headers["X-Sendfile"]
  end

  test "returns 404 when there is no succeeded execution" do
    login_as(user)
    create_failed_query_execution(query: query)
    get_csv latest_csv_query_executions_path(query)
    assert_response :not_found
  end

  test "returns 404 when the CSV file is missing on disk" do
    login_as(user)
    create_succeeded_query_execution(query: query)
    get_csv latest_csv_query_executions_path(query)
    assert_response :not_found
  end
end
