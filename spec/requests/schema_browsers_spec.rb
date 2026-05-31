require "rails_helper"

RSpec.describe "SchemaBrowsers", type: :request do
  let(:user) { create(:user, :member, password: "password") }
  let!(:connection) { create(:bigquery_connection) }

  let(:schema_structure) do
    {
      fetched_at: Time.current,
      datasets: [
        {
          dataset_id: "analytics",
          name: "Analytics",
          tables: [
            {
              table_id: "events",
              table_type: "TABLE",
              columns: [
                { column_name: "user_id", data_type: "STRING",
                  is_nullable: true, ordinal_position: 1 }
              ]
            }
          ]
        }
      ]
    }
  end

  def login_as(u, password: "password")
    post session_path, params: { email: u.email, password: password }
  end

  describe "GET /schema_browser" do
    context "when logged in" do
      before { login_as(user) }

      it "fetches the cached schema (syncing on first access) and renders the tree" do
        expect_any_instance_of(Bigquery::Connection)
          .to receive(:cached_schema).and_return(schema_structure)

        get schema_browser_path

        expect(response).to have_http_status(:ok)
        expect(response.body).to include("analytics")
        expect(response.body).to include("events")
        expect(response.body).to include("user_id")
      end
    end

    context "when not logged in" do
      it "redirects to login" do
        create(:user)
        get schema_browser_path
        expect(response).to redirect_to(new_session_path)
      end
    end
  end
end
