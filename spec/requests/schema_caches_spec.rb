require "rails_helper"

RSpec.describe "SchemaCaches", type: :request do
  let(:user) { create(:user, :member, password: "password") }
  let!(:connection) { create(:bigquery_connection) }

  def login_as(u, password: "password")
    post session_path, params: { email: u.email, password: password }
  end

  def stub_sync!
    allow_any_instance_of(Bigquery::Connection)
      .to receive(:sync_schema!)
      .and_return({ fetched_at: Time.current, datasets: [] })
  end

  describe "POST /schema_caches/refresh" do
    context "when logged in" do
      before do
        login_as(user)
        stub_sync!
      end

      it "forces a re-sync and redirects back to the schema browser" do
        post refresh_schema_caches_path

        expect(response).to have_http_status(:found)
        expect(response).to redirect_to(schema_browser_path)
      end

      it "calls sync_schema! with force: true on the connection" do
        expect_any_instance_of(Bigquery::Connection)
          .to receive(:sync_schema!).with(force: true)
          .and_return({ fetched_at: Time.current, datasets: [] })

        post refresh_schema_caches_path
      end
    end

    context "when not logged in" do
      it "redirects to login" do
        create(:user) # セットアップ誘導回避
        post refresh_schema_caches_path
        expect(response).to redirect_to(new_session_path)
      end
    end
  end
end
