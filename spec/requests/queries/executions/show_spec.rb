require "rails_helper"

# 過去実行の結果再表示エンドポイント（トピック17）。
# GET /queries/:query_id/executions/:id。所有クエリのみ（他人の id は 404）。
RSpec.describe "Queries::Executions#show", type: :request do
  let(:user) { create(:user, :member, password: "password") }
  let(:other_user) { create(:user, :member, password: "password") }
  let(:connection) { create(:bigquery_connection, maximum_bytes_billed: nil) }
  let(:query) { create(:query, user: user, bigquery_connection: connection, sql_body: "SELECT 1") }

  def login_as(who, password: "password")
    post session_path, params: { email: who.email, password: password }
  end

  describe "access control" do
    it "redirects unauthenticated requests to login" do
      create(:user) # セットアップ誘導回避
      execution = create(:query_execution, :succeeded, query: query)
      get query_execution_path(query, execution)
      expect(response).to redirect_to(new_session_path)
    end

    it "returns 404 for another user's query" do
      login_as(user)
      foreign = create(:query, user: other_user, bigquery_connection: connection)
      execution = create(:query_execution, :succeeded, query: foreign)
      get query_execution_path(foreign, execution)
      expect(response).to have_http_status(:not_found)
    end

    it "returns 404 for an execution that does not belong to the query" do
      login_as(user)
      other_query = create(:query, user: user, bigquery_connection: connection)
      execution = create(:query_execution, :succeeded, query: other_query)
      get query_execution_path(query, execution)
      expect(response).to have_http_status(:not_found)
    end
  end

  context "as the owner" do
    before { login_as(user) }

    it "renders the result table from the stored blob for a succeeded execution" do
      execution = create(:query_execution, :succeeded, query: query, result_row_count: 2)
      execution.store_result(
        [ { "name" => "id", "type" => "INTEGER" }, { "name" => "name", "type" => "STRING" } ],
        [ [ 1, "alice" ], [ 2, "bob" ] ]
      )
      execution.save!

      get query_execution_path(query, execution)

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("alice")
      expect(response.body).to include("bob")
      expect(response.body).to include("id")
    end

    it "renders the error state for a failed execution" do
      execution = create(:query_execution, :failed, query: query, error_message: "invalid query: boom")
      get query_execution_path(query, execution)
      expect(response).to have_http_status(:ok)
      expect(response.body).to include("invalid query: boom")
    end

    it "renders the running state for a running execution" do
      execution = create(:query_execution, :running, query: query)
      get query_execution_path(query, execution)
      expect(response).to have_http_status(:ok)
      expect(response.body).to include("実行中")
    end
  end
end
