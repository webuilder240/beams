require "rails_helper"

RSpec.describe "Bigquery::Connections", type: :request do
  let(:admin) { create(:user, :admin, password: "password") }
  let(:member) { create(:user, :member, password: "password") }

  let(:valid_json) { '{"type":"service_account","project_id":"my-project-123"}' }
  let(:valid_attributes) do
    # コスト上限は GB 入力（仮想属性）→ バイト保存。
    { name: "本番", project_id: "my-project-123", service_account_json: valid_json, maximum_bytes_billed_gb: "10" }
  end

  def login_as(user, password: "password")
    post session_path, params: { email: user.email, password: password }
  end

  describe "access control (member rejected)" do
    before { login_as(member) }

    it "blocks members from the index" do
      get bigquery_connections_path
      expect(response).to redirect_to(root_path)
    end

    it "blocks members from creating connections" do
      expect {
        post bigquery_connections_path, params: { bigquery_connection: valid_attributes }
      }.not_to change(Bigquery::Connection, :count)
      expect(response).to redirect_to(root_path)
    end
  end

  describe "access control (unauthenticated rejected)" do
    it "redirects to login" do
      create(:user) # 初回セットアップ誘導を回避（ユーザーが存在する状態）
      get bigquery_connections_path
      expect(response).to redirect_to(new_session_path)
    end
  end

  context "as an admin" do
    before { login_as(admin) }

    describe "GET /bigquery/connections" do
      it "lists connections without exposing the SA JSON" do
        secret = "TOP_SECRET_KEY_MATERIAL"
        create(:bigquery_connection, name: "本番DB", service_account_json: %({"type":"service_account","private_key":"#{secret}"}))
        get bigquery_connections_path
        expect(response).to have_http_status(:ok)
        expect(response.body).to include("本番DB")
        expect(response.body).not_to include(secret)
      end
    end

    describe "GET /bigquery/connections/new" do
      it "renders the new form" do
        get new_bigquery_connection_path
        expect(response).to have_http_status(:ok)
      end
    end

    describe "POST /bigquery/connections" do
      it "creates a connection" do
        expect {
          post bigquery_connections_path, params: { bigquery_connection: valid_attributes }
        }.to change(Bigquery::Connection, :count).by(1)
        expect(response).to redirect_to(bigquery_connections_path)
        created = Bigquery::Connection.find_by(name: "本番")
        expect(created.project_id).to eq("my-project-123")
        expect(created.service_account_json).to eq(valid_json)
      end

      it "saves the GB cost limit as bytes (10 GB → 10 * 1024^3 bytes)" do
        post bigquery_connections_path, params: { bigquery_connection: valid_attributes }
        created = Bigquery::Connection.find_by(name: "本番")
        expect(created.maximum_bytes_billed).to eq(10 * (1024**3))
        expect(created.maximum_bytes_billed_gb).to eq(10.0)
      end

      it "treats a blank GB limit as no limit (nil)" do
        post bigquery_connections_path, params: {
          bigquery_connection: valid_attributes.merge(maximum_bytes_billed_gb: "")
        }
        created = Bigquery::Connection.find_by(name: "本番")
        expect(created.maximum_bytes_billed).to be_nil
      end

      it "re-renders on invalid input" do
        expect {
          post bigquery_connections_path, params: {
            bigquery_connection: valid_attributes.merge(service_account_json: "{not json")
          }
        }.not_to change(Bigquery::Connection, :count)
        expect(response).to have_http_status(:unprocessable_content)
      end
    end

    describe "GET /bigquery/connections/:id/edit" do
      it "renders the edit form without exposing the SA JSON plaintext" do
        secret = "EDIT_PAGE_SECRET_KEY"
        connection = create(:bigquery_connection, service_account_json: %({"type":"service_account","private_key":"#{secret}"}))
        get edit_bigquery_connection_path(connection)
        expect(response).to have_http_status(:ok)
        expect(response.body).not_to include(secret)
      end
    end

    describe "PATCH /bigquery/connections/:id" do
      it "updates the name and project_id" do
        connection = create(:bigquery_connection)
        patch bigquery_connection_path(connection), params: {
          bigquery_connection: { name: "更新後", project_id: "new-project-9", service_account_json: "" }
        }
        expect(response).to redirect_to(bigquery_connections_path)
        expect(connection.reload.name).to eq("更新後")
        expect(connection.project_id).to eq("new-project-9")
      end

      it "keeps the existing SA JSON when the field is left blank" do
        original = '{"type":"service_account","project_id":"keep-me"}'
        connection = create(:bigquery_connection, service_account_json: original)
        patch bigquery_connection_path(connection), params: {
          bigquery_connection: { name: "名前だけ変更", service_account_json: "" }
        }
        expect(connection.reload.service_account_json).to eq(original)
      end

      it "replaces the SA JSON when a new value is provided" do
        connection = create(:bigquery_connection)
        new_json = '{"type":"service_account","project_id":"replaced"}'
        patch bigquery_connection_path(connection), params: {
          bigquery_connection: { service_account_json: new_json }
        }
        expect(connection.reload.service_account_json).to eq(new_json)
      end

      it "re-renders on invalid input" do
        connection = create(:bigquery_connection)
        patch bigquery_connection_path(connection), params: {
          bigquery_connection: { project_id: "invalid id!" }
        }
        expect(response).to have_http_status(:unprocessable_content)
      end
    end

    describe "DELETE /bigquery/connections/:id" do
      it "deletes the connection" do
        connection = create(:bigquery_connection)
        expect {
          delete bigquery_connection_path(connection)
        }.to change(Bigquery::Connection, :count).by(-1)
        expect(response).to redirect_to(bigquery_connections_path)
      end
    end
  end
end
