require "rails_helper"

RSpec.describe "Admin::RedashSources", type: :request do
  let(:admin) { create(:user, :admin, password: "password") }
  let(:member) { create(:user, :member, password: "password") }

  let(:valid_attributes) do
    { name: "社内 Redash", url: "https://redash.example.com", api_key: "redash_api_key_123" }
  end

  def login_as(user, password: "password")
    post session_path, params: { email: user.email, password: password }
  end

  before do
    # SSRF ガード（URL バリデーション）を通すため、Resolv をスタブ。
    allow(Resolv).to receive(:getaddresses).and_return([ "203.0.113.10" ])
  end

  describe "access control" do
    it "blocks members from index" do
      login_as(member)
      get admin_redash_sources_path
      expect(response).to redirect_to(root_path)
    end

    it "blocks unauthenticated visitors" do
      create(:user) # 初回セットアップ誘導回避
      get admin_redash_sources_path
      expect(response).to redirect_to(new_session_path)
    end

    it "blocks members from creating sources" do
      login_as(member)
      expect {
        post admin_redash_sources_path, params: { redash_source: valid_attributes }
      }.not_to change(RedashSource, :count)
      expect(response).to redirect_to(root_path)
    end
  end

  context "as an admin" do
    before { login_as(admin) }

    describe "GET /admin/redash_sources" do
      it "lists sources without exposing the api_key" do
        create(:redash_source, name: "プロダクション Redash", api_key: "VERY_SECRET_KEY")
        get admin_redash_sources_path
        expect(response).to have_http_status(:ok)
        expect(response.body).to include("プロダクション Redash")
        expect(response.body).not_to include("VERY_SECRET_KEY")
      end
    end

    describe "GET /admin/redash_sources/new" do
      it "renders the new form" do
        get new_admin_redash_source_path
        expect(response).to have_http_status(:ok)
      end
    end

    describe "POST /admin/redash_sources" do
      it "creates a redash source" do
        expect {
          post admin_redash_sources_path, params: { redash_source: valid_attributes }
        }.to change(RedashSource, :count).by(1)
        expect(response).to redirect_to(admin_redash_sources_path)
        created = RedashSource.find_by(name: "社内 Redash")
        expect(created.url).to eq("https://redash.example.com")
        expect(created.api_key).to eq("redash_api_key_123")
      end

      it "re-renders on invalid input" do
        expect {
          post admin_redash_sources_path, params: { redash_source: valid_attributes.merge(name: "") }
        }.not_to change(RedashSource, :count)
        expect(response).to have_http_status(:unprocessable_content)
      end
    end

    describe "GET /admin/redash_sources/:id/edit" do
      it "renders the edit form without showing the encrypted api_key" do
        record = create(:redash_source, api_key: "EDIT_SECRET")
        get edit_admin_redash_source_path(record)
        expect(response).to have_http_status(:ok)
        expect(response.body).not_to include("EDIT_SECRET")
      end
    end

    describe "PATCH /admin/redash_sources/:id" do
      it "updates the source while keeping the api_key when blank" do
        record = create(:redash_source, name: "旧名", api_key: "ORIGINAL")
        patch admin_redash_source_path(record), params: {
          redash_source: { name: "新名", url: "https://redash.example.com", api_key: "" }
        }
        expect(response).to redirect_to(admin_redash_sources_path)
        record.reload
        expect(record.name).to eq("新名")
        expect(record.api_key).to eq("ORIGINAL")
      end

      it "updates the api_key when a new value is supplied" do
        record = create(:redash_source, api_key: "ORIGINAL")
        patch admin_redash_source_path(record), params: {
          redash_source: { name: record.name, url: record.url, api_key: "NEW_KEY" }
        }
        expect(response).to redirect_to(admin_redash_sources_path)
        expect(record.reload.api_key).to eq("NEW_KEY")
      end
    end

    describe "DELETE /admin/redash_sources/:id" do
      it "deletes the source" do
        record = create(:redash_source)
        expect { delete admin_redash_source_path(record) }.to change(RedashSource, :count).by(-1)
        expect(response).to redirect_to(admin_redash_sources_path)
      end
    end
  end
end
