require "rails_helper"

RSpec.describe "Queries::Executions::CsvExports", type: :request do
  let(:user) { create(:user, :member, password: "password") }
  let(:other_user) { create(:user, :member, password: "password") }
  let(:connection) { create(:bigquery_connection) }
  let(:query) { create(:query, user: user, bigquery_connection: connection) }

  def login_as(who, password: "password")
    post session_path, params: { email: who.email, password: password }
  end

  # Thruster（本番）が付与する X-Sendfile-Type を模した GET。
  # これにより Rack::Sendfile が応答に X-Sendfile ヘッダーを立てる。
  def get_csv(path_helper)
    get path_helper, headers: { "X-Sendfile-Type" => "X-Sendfile" }
  end

  # ジョブが書き出すはずの全件 CSV(.gz) をテスト用に用意する。
  def write_csv_for(execution)
    dir = Rails.root.join("storage/csv")
    FileUtils.mkdir_p(dir)
    path = dir.join("#{execution.id}.csv.gz")
    Zlib::GzipWriter.open(path) { |gz| gz.write("n\n1\n2\n") }
    path
  end

  after { FileUtils.rm_rf(Rails.root.join("storage/csv")) }

  describe "access control" do
    it "redirects unauthenticated requests to login" do
      create(:user)
      get_csv latest_csv_query_executions_path(query)
      expect(response).to redirect_to(new_session_path)
    end

    it "returns 404 for another user's query" do
      login_as(user)
      foreign = create(:query, user: other_user, bigquery_connection: connection)
      get latest_csv_query_executions_path(foreign)
      expect(response).to have_http_status(:not_found)
    end
  end

  context "as the owner" do
    before { login_as(user) }

    it "sends the latest succeeded execution's CSV via X-Sendfile" do
      execution = create(:query_execution, :succeeded, query: query)
      path = write_csv_for(execution)

      get_csv latest_csv_query_executions_path(query)

      expect(response).to have_http_status(:ok)
      expect(response.headers["Content-Type"]).to include("text/csv")
      expect(response.headers["X-Sendfile"]).to eq(path.to_s)
    end

    it "serves the full CSV even when the displayed result was truncated" do
      execution = create(:query_execution, :succeeded, query: query, result_truncated: true)
      path = write_csv_for(execution)

      get_csv latest_csv_query_executions_path(query)

      expect(response).to have_http_status(:ok)
      expect(response.headers["X-Sendfile"]).to eq(path.to_s)
    end

    it "returns 404 when there is no succeeded execution" do
      create(:query_execution, :failed, query: query)
      get_csv latest_csv_query_executions_path(query)
      expect(response).to have_http_status(:not_found)
    end

    it "returns 404 when the CSV file is missing on disk" do
      create(:query_execution, :succeeded, query: query)
      get_csv latest_csv_query_executions_path(query)
      expect(response).to have_http_status(:not_found)
    end
  end
end
