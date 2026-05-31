require "rails_helper"

RSpec.describe "Queries::DryRuns", type: :request do
  let(:user) { create(:user, :member, password: "password") }
  let(:other_user) { create(:user, :member, password: "password") }
  let(:connection) { create(:bigquery_connection, maximum_bytes_billed: nil) }
  let(:query) { create(:query, user: user, bigquery_connection: connection) }

  def login_as(who, password: "password")
    post session_path, params: { email: who.email, password: password }
  end

  # DryRun PORO をスタブして BigQuery API を呼ばせない。
  def stub_dry_run(bytes:)
    fake = instance_double(DryRun, call: { bytes_processed: bytes })
    allow(DryRun).to receive(:new).and_return(fake)
    fake
  end

  describe "access control" do
    it "redirects unauthenticated requests to login" do
      create(:user) # セットアップ誘導回避
      post query_dry_run_path(query), params: { sql: "SELECT 1" }
      expect(response).to redirect_to(new_session_path)
    end
  end

  context "as a logged-in user" do
    before { login_as(user) }

    it "returns the estimate for the current user's query" do
      stub_dry_run(bytes: 5_368_709_120) # 5 GiB

      post query_dry_run_path(query), params: { sql: "SELECT 1" }, as: :json

      expect(response).to have_http_status(:ok)
      body = response.parsed_body
      expect(body["gb"]).to eq(5.0)
      expect(body["yen"]).to eq(4.75)
      expect(body["over_limit"]).to be(false)
      expect(body["error"]).to be_nil
    end

    it "uses the SQL from the request body, not the saved query body" do
      fake = stub_dry_run(bytes: 100)

      post query_dry_run_path(query), params: { sql: "SELECT live_edit" }, as: :json

      expect(DryRun).to have_received(:new).with(connection, "SELECT live_edit")
      expect(fake).to have_received(:call)
    end

    it "reports over_limit with the limit (GB) and an error message when exceeded" do
      connection.update!(maximum_bytes_billed: 1_000) # ~very small
      stub_dry_run(bytes: 5_368_709_120) # 5 GiB >> 1000 bytes

      post query_dry_run_path(query), params: { sql: "SELECT 1" }, as: :json

      expect(response).to have_http_status(:ok)
      body = response.parsed_body
      expect(body["over_limit"]).to be(true)
      expect(body["error"]).to be_present
      expect(body["limit_gb"]).to eq(CostEstimate.bytes_to_gb(1_000))
    end

    it "stays under limit when bytes are within maximum_bytes_billed" do
      connection.update!(maximum_bytes_billed: 10_000_000_000) # 10 GB
      stub_dry_run(bytes: 5_368_709_120) # 5 GiB

      post query_dry_run_path(query), params: { sql: "SELECT 1" }, as: :json

      expect(response.parsed_body["over_limit"]).to be(false)
    end

    it "returns a JSON error when BigQuery raises" do
      fake = instance_double(DryRun)
      allow(DryRun).to receive(:new).and_return(fake)
      allow(fake).to receive(:call).and_raise(Google::Cloud::Error.new("invalid query: syntax error"))

      post query_dry_run_path(query), params: { sql: "SELECT bad" }, as: :json

      expect(response).to have_http_status(:unprocessable_content)
      body = response.parsed_body
      expect(body["error"]).to include("syntax error")
      expect(body["over_limit"]).to be(false)
    end

    it "does not dry-run another user's query (404)" do
      foreign = create(:query, user: other_user)

      post query_dry_run_path(foreign), params: { sql: "SELECT 1" }, as: :json

      expect(response).to have_http_status(:not_found)
    end
  end
end
