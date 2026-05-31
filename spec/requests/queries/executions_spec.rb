require "rails_helper"

RSpec.describe "Queries::Executions", type: :request do
  let(:user) { create(:user, :member, password: "password") }
  let(:other_user) { create(:user, :member, password: "password") }
  let(:connection) { create(:bigquery_connection, maximum_bytes_billed: nil) }
  let(:query) { create(:query, user: user, bigquery_connection: connection, sql_body: "SELECT 1") }

  def login_as(who, password: "password")
    post session_path, params: { email: who.email, password: password }
  end

  before do
    allow(QueryExecutionJob).to receive(:perform_later)
  end

  describe "access control" do
    it "redirects unauthenticated requests to login" do
      create(:user) # セットアップ誘導回避
      post query_executions_path(query)
      expect(response).to redirect_to(new_session_path)
    end

    it "returns 404 for another user's query" do
      login_as(user)
      foreign = create(:query, user: other_user, bigquery_connection: connection)
      post query_executions_path(foreign)
      expect(response).to have_http_status(:not_found)
    end
  end

  context "as the owner" do
    before { login_as(user) }

    it "creates a running execution and enqueues the job" do
      expect {
        post query_executions_path(query)
      }.to change(QueryExecution, :count).by(1)

      execution = QueryExecution.last
      expect(execution.query).to eq(query)
      expect(QueryExecutionJob).to have_received(:perform_later).with(execution, {})
      expect(response).to have_http_status(:see_other).or have_http_status(:created)
    end

    context "with parameters" do
      let(:query) do
        create(:query, user: user, bigquery_connection: connection,
                       sql_body: "SELECT * FROM t WHERE id = {{ id:number }}")
      end

      it "passes whitelisted parameter values to the job" do
        post query_executions_path(query), params: { query_params: { id: "5" } }

        execution = QueryExecution.last
        expect(QueryExecutionJob).to have_received(:perform_later)
          .with(execution, { "id" => "5" })
      end

      it "does not enqueue or create when a required parameter is missing" do
        expect {
          post query_executions_path(query), params: { query_params: { id: "" } }
        }.not_to change(QueryExecution, :count)

        expect(QueryExecutionJob).not_to have_received(:perform_later)
        expect(response).to have_http_status(:unprocessable_content)
      end
    end

    context "when at the concurrency limit" do
      it "creates the execution as pending" do
        create_list(:query_execution, 20, :running, query: query)

        post query_executions_path(query)

        expect(QueryExecution.last).to be_pending
        expect(QueryExecutionJob).to have_received(:perform_later)
      end
    end
  end
end
