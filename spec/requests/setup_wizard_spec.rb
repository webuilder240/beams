require "rails_helper"

RSpec.describe "SetupWizard", type: :request do
  let(:valid_json) { '{"type":"service_account","project_id":"my-project-123"}' }

  describe "初回起動検知（ApplicationController）" do
    context "when there are no users" do
      it "redirects an arbitrary URL to the setup wizard" do
        get root_path
        expect(response).to redirect_to(setup_step1_path)
      end

      it "redirects the bigquery connections index to the setup wizard" do
        get bigquery_connections_path
        expect(response).to redirect_to(setup_step1_path)
      end

      it "does not redirect the wizard itself (no loop)" do
        get setup_step1_path
        expect(response).to have_http_status(:ok)
      end
    end

    context "when at least one user exists" do
      before { create(:user, :admin) }

      it "does not redirect to the setup wizard" do
        get new_session_path
        expect(response).to have_http_status(:ok)
      end
    end
  end

  describe "ウィザード完了済みでのリダイレクト" do
    before { create(:user, :admin) }

    it "redirects /setup to the root" do
      get setup_path
      expect(response).to redirect_to(root_path)
    end

    it "redirects step1 to the root" do
      get setup_step1_path
      expect(response).to redirect_to(root_path)
    end

    it "redirects a POST to step1 to the root" do
      post setup_step1_path, params: { user: { email: "x@example.com", password: "password", password_confirmation: "password" } }
      expect(response).to redirect_to(root_path)
    end
  end

  describe "GET /setup (entry point)" do
    it "redirects to step1 when no users exist" do
      get setup_path
      expect(response).to redirect_to(setup_step1_path)
    end
  end

  describe "ステップ① admin 作成" do
    describe "GET /setup/step1" do
      it "renders the form" do
        get setup_step1_path
        expect(response).to have_http_status(:ok)
      end
    end

    describe "POST /setup/step1" do
      it "creates an admin user, establishes a session, and advances to step2" do
        expect {
          post setup_step1_path, params: {
            user: { email: "admin@example.com", password: "password", password_confirmation: "password" }
          }
        }.to change(User, :count).by(1)

        created = User.find_by(email: "admin@example.com")
        expect(created.admin?).to be(true)
        expect(session[:user_id]).to eq(created.id)
        expect(response).to redirect_to(setup_step2_path)
      end

      it "re-renders the form on validation error" do
        expect {
          post setup_step1_path, params: {
            user: { email: "admin@example.com", password: "password", password_confirmation: "mismatch" }
          }
        }.not_to change(User, :count)
        expect(response).to have_http_status(:unprocessable_content)
      end
    end
  end

  describe "ステップ間の進行制御" do
    it "redirects step2 back to step1 when no user exists" do
      get setup_step2_path
      expect(response).to redirect_to(setup_step1_path)
    end

    context "after step1 is complete (an admin exists and is logged in)" do
      before do
        post setup_step1_path, params: {
          user: { email: "admin@example.com", password: "password", password_confirmation: "password" }
        }
      end

      it "allows step2" do
        get setup_step2_path
        expect(response).to have_http_status(:ok)
      end

      it "redirects step3 back to step2 when no connection exists" do
        get setup_step3_path
        expect(response).to redirect_to(setup_step2_path)
      end

      it "redirects step4 back to step2 when no connection exists" do
        get setup_step4_path
        expect(response).to redirect_to(setup_step2_path)
      end
    end
  end

  describe "ステップ② 接続登録" do
    before do
      post setup_step1_path, params: {
        user: { email: "admin@example.com", password: "password", password_confirmation: "password" }
      }
    end

    describe "GET /setup/step2" do
      it "renders the form" do
        get setup_step2_path
        expect(response).to have_http_status(:ok)
      end
    end

    describe "POST /setup/step2" do
      it "creates a connection and advances to step3" do
        expect {
          post setup_step2_path, params: {
            bigquery_connection: { name: "本番", project_id: "my-project-123", service_account_json: valid_json }
          }
        }.to change(Bigquery::Connection, :count).by(1)

        created = Bigquery::Connection.find_by(name: "本番")
        expect(created.project_id).to eq("my-project-123")
        expect(created.maximum_bytes_billed).to be_nil
        expect(response).to redirect_to(setup_step3_path)
      end

      it "re-renders the form on validation error" do
        expect {
          post setup_step2_path, params: {
            bigquery_connection: { name: "本番", project_id: "my-project-123", service_account_json: "{not json" }
          }
        }.not_to change(Bigquery::Connection, :count)
        expect(response).to have_http_status(:unprocessable_content)
      end
    end
  end

  describe "ステップ③ 接続テスト" do
    before do
      post setup_step1_path, params: {
        user: { email: "admin@example.com", password: "password", password_confirmation: "password" }
      }
      post setup_step2_path, params: {
        bigquery_connection: { name: "本番", project_id: "my-project-123", service_account_json: valid_json }
      }
    end

    it "shows a success message and a next button when the test passes" do
      allow_any_instance_of(Bigquery::Connection).to receive(:test_connection).and_return({ success: true })
      get setup_step3_path
      expect(response).to have_http_status(:ok)
      expect(response.body).to include("step4")
    end

    it "shows the missing permissions when the test fails" do
      allow_any_instance_of(Bigquery::Connection).to receive(:test_connection).and_return(
        { success: false, missing_permissions: [ "bigquery.jobs.create" ], message: "Access Denied" }
      )
      get setup_step3_path
      expect(response).to have_http_status(:ok)
      expect(response.body).to include("bigquery.jobs.create")
    end
  end

  describe "ステップ④ コスト上限" do
    before do
      post setup_step1_path, params: {
        user: { email: "admin@example.com", password: "password", password_confirmation: "password" }
      }
      post setup_step2_path, params: {
        bigquery_connection: { name: "本番", project_id: "my-project-123", service_account_json: valid_json }
      }
    end

    describe "GET /setup/step4" do
      it "renders the form" do
        get setup_step4_path
        expect(response).to have_http_status(:ok)
      end
    end

    describe "POST /setup/step4" do
      it "sets the maximum_bytes_billed and redirects to root" do
        post setup_step4_path, params: { bigquery_connection: { maximum_bytes_billed: 5_000_000 } }
        expect(Bigquery::Connection.first.maximum_bytes_billed).to eq(5_000_000)
        expect(response).to redirect_to(root_path)
      end

      it "skips and leaves the limit nil when no value is provided" do
        post setup_step4_path, params: { bigquery_connection: { maximum_bytes_billed: "" } }
        expect(Bigquery::Connection.first.maximum_bytes_billed).to be_nil
        expect(response).to redirect_to(root_path)
      end
    end
  end
end
