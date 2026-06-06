require "rails_helper"

RSpec.describe "RedashImports", type: :request do
  let(:user) { create(:user, :member, password: "password") }
  let!(:redash_source) do
    allow(Resolv).to receive(:getaddresses).and_return([ "203.0.113.10" ])
    create(:redash_source,
           name: "Demo Redash",
           url: "https://redash.example.com",
           api_key: "k1")
  end
  let!(:bq_connection) { create(:bigquery_connection, name: "BigQuery 本番") }

  def login_as(user, password: "password")
    post session_path, params: { email: user.email, password: password }
  end

  before { login_as(user) }

  describe "GET /redash_import/new" do
    it "renders the source selection form when at least one source exists" do
      get new_redash_import_path
      expect(response).to have_http_status(:ok)
      expect(response.body).to include("Demo Redash")
    end

    it "redirects to login when not authenticated" do
      delete session_path
      get new_redash_import_path
      expect(response).to redirect_to(new_session_path)
    end
  end

  describe "GET /redash_import/:id/index_queries" do
    it "lists Redash queries with checkboxes and a BigQuery connection selector" do
      list = {
        "count" => 2, "page" => 1, "page_size" => 25,
        "results" => [
          { "id" => 10, "name" => "Active users" },
          { "id" => 11, "name" => "Revenue" }
        ]
      }.to_json
      stub_request(:get, /redash\.example\.com\/api\/queries/)
        .to_return(status: 200, body: list, headers: { "Content-Type" => "application/json" })

      get index_queries_redash_import_path, params: { redash_source_id: redash_source.id }

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("Active users")
      expect(response.body).to include("Revenue")
      expect(response.body).to include("BigQuery 本番")
    end

    it "shows an error when the Redash API key is invalid (401)" do
      stub_request(:get, /redash\.example\.com\/api\/queries/).to_return(status: 401)

      get index_queries_redash_import_path, params: { redash_source_id: redash_source.id }

      expect(response).to redirect_to(new_redash_import_path)
      expect(flash[:alert]).to match(/APIキー|無効|認証/)
    end

    it "shows an error when the Redash server is unreachable (timeout)" do
      stub_request(:get, /redash\.example\.com\/api\/queries/).to_timeout

      get index_queries_redash_import_path, params: { redash_source_id: redash_source.id }

      expect(response).to redirect_to(new_redash_import_path)
      expect(flash[:alert]).to match(/接続|タイムアウト/)
    end
  end

  describe "POST /redash_import" do
    let(:detail_body_10) do
      {
        "id" => 10, "name" => "Active users",
        "query" => "SELECT count(*) FROM users WHERE created_at >= {{ start_date }}",
        "options" => { "parameters" => [
          { "name" => "start_date", "type" => "date" }
        ] }
      }.to_json
    end
    let(:detail_body_11) do
      {
        "id" => 11, "name" => "Revenue",
        "query" => "SELECT SUM(amount) FROM payments",
        "options" => { "parameters" => [] }
      }.to_json
    end

    it "creates Query records and renders the result with success counts" do
      stub_request(:get, "https://redash.example.com/api/queries/10")
        .to_return(status: 200, body: detail_body_10)
      stub_request(:get, "https://redash.example.com/api/queries/11")
        .to_return(status: 200, body: detail_body_11)

      expect {
        post redash_import_path, params: {
          redash_source_id: redash_source.id,
          bigquery_connection_id: bq_connection.id,
          query_ids: %w[10 11]
        }
      }.to change(Query, :count).by(2)

      expect(response).to have_http_status(:ok)
      active_users = Query.find_by(title: "Active users")
      expect(active_users.user_id).to eq(user.id)
      expect(active_users.bigquery_connection_id).to eq(bq_connection.id)
      expect(active_users.query_parameters.pluck(:name, :param_type))
        .to eq([ [ "start_date", "date" ] ])

      expect(response.body).to include("Active users")
      expect(response.body).to include("Revenue")
      expect(response.body).to include("成功")
    end

    it "continues on partial failure (one query 404s, another succeeds)" do
      stub_request(:get, "https://redash.example.com/api/queries/10")
        .to_return(status: 200, body: detail_body_10)
      stub_request(:get, "https://redash.example.com/api/queries/11").to_return(status: 404)

      expect {
        post redash_import_path, params: {
          redash_source_id: redash_source.id,
          bigquery_connection_id: bq_connection.id,
          query_ids: %w[10 11]
        }
      }.to change(Query, :count).by(1)

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("Active users")
      expect(response.body).to match(/失敗|エラー/)
    end

    it "rejects when no BigQuery connection is selected" do
      expect {
        post redash_import_path, params: {
          redash_source_id: redash_source.id,
          bigquery_connection_id: "",
          query_ids: %w[10]
        }
      }.not_to change(Query, :count)
      expect(response).to redirect_to(new_redash_import_path)
      expect(flash[:alert]).to match(/BigQuery|接続/)
    end

    it "rejects when no queries are checked" do
      expect {
        post redash_import_path, params: {
          redash_source_id: redash_source.id,
          bigquery_connection_id: bq_connection.id,
          query_ids: []
        }
      }.not_to change(Query, :count)
      expect(response).to redirect_to(index_queries_redash_import_path(redash_source_id: redash_source.id))
      expect(flash[:alert]).to match(/選択|クエリ/)
    end

    it "exposes warnings from RedashQueryPayload in the result" do
      detail_with_warning = {
        "id" => 12, "name" => "Datetime sample",
        "query" => "SELECT 1",
        "options" => { "parameters" => [ { "name" => "ts", "type" => "datetime-local" } ] }
      }.to_json
      stub_request(:get, "https://redash.example.com/api/queries/12")
        .to_return(status: 200, body: detail_with_warning)

      post redash_import_path, params: {
        redash_source_id: redash_source.id,
        bigquery_connection_id: bq_connection.id,
        query_ids: %w[12]
      }

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("Datetime sample")
      expect(response.body).to match(/警告|datetime-local/)
    end
  end
end
