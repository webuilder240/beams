require "rails_helper"

RSpec.describe "Dashboards", type: :request do
  let(:user) { create(:user, :member, password: "password") }
  let(:other_user) { create(:user, :member, password: "password") }

  def login_as(who, password: "password")
    post session_path, params: { email: who.email, password: password }
  end

  describe "authentication" do
    before { create(:user) } # セットアップ誘導回避

    it "redirects GET /dashboards to login when unauthenticated" do
      get dashboards_path
      expect(response).to have_http_status(:found)
      expect(response).to redirect_to(new_session_path)
    end

    it "redirects POST /dashboards to login when unauthenticated" do
      post dashboards_path, params: { dashboard: { title: "x" } }
      expect(response).to redirect_to(new_session_path)
    end
  end

  describe "GET /dashboards" do
    before { login_as(user) }

    it "lists all dashboards ordered by updated_at desc" do
      old = create(:dashboard, user: user, title: "古い", updated_at: 2.days.ago)
      recent = create(:dashboard, user: other_user, title: "新しい", updated_at: 1.hour.ago)

      get dashboards_path
      expect(response).to have_http_status(:ok)
      expect(response.body).to include("古い")
      # 全ユーザーのダッシュボードが見える（§4.9）
      expect(response.body).to include("新しい")
      expect(response.body.index("新しい")).to be < response.body.index("古い")
      expect([ old, recent ]).to all(be_present)
    end

    it "filters by title partial match with ?q=" do
      create(:dashboard, user: user, title: "売上ダッシュボード")
      create(:dashboard, user: other_user, title: "ユーザー分析")

      get dashboards_path(q: "売上")
      expect(response).to have_http_status(:ok)
      expect(response.body).to include("売上ダッシュボード")
      expect(response.body).not_to include("ユーザー分析")
    end

    it "shows no dashboards when nothing matches ?q=" do
      create(:dashboard, user: user, title: "売上ダッシュボード")

      get dashboards_path(q: "存在しないキーワード")
      expect(response).to have_http_status(:ok)
      expect(response.body).not_to include("売上ダッシュボード")
      expect(response.body).to include("まだダッシュボードがありません")
    end

    it "returns all dashboards when q is blank" do
      create(:dashboard, user: user, title: "売上ダッシュボード")
      create(:dashboard, user: other_user, title: "ユーザー分析")

      get dashboards_path(q: "")
      expect(response.body).to include("売上ダッシュボード")
      expect(response.body).to include("ユーザー分析")
    end
  end

  describe "GET /dashboards/:id" do
    before { login_as(user) }

    it "shows another user's dashboard (org full-open §4.9)" do
      foreign = create(:dashboard, user: other_user, title: "他人のダッシュボード")
      get dashboard_path(foreign)
      expect(response).to have_http_status(:ok)
      expect(response.body).to include("他人のダッシュボード")
    end
  end

  describe "POST /dashboards" do
    before { login_as(user) }

    it "creates a dashboard owned by current_user" do
      expect {
        post dashboards_path, params: { dashboard: { title: "売上", description: "概要" } }
      }.to change(Dashboard, :count).by(1)

      dashboard = Dashboard.last
      expect(dashboard.user).to eq(user)
      expect(dashboard.title).to eq("売上")
      expect(response).to redirect_to(dashboard_path(dashboard))
    end

    it "re-renders new on invalid input" do
      post dashboards_path, params: { dashboard: { title: "" } }
      expect(response).to have_http_status(:unprocessable_content)
    end
  end

  describe "PATCH /dashboards/:id" do
    before { login_as(user) }

    it "updates another user's dashboard (org full-open §4.9)" do
      foreign = create(:dashboard, user: other_user, title: "旧題")
      patch dashboard_path(foreign), params: { dashboard: { title: "新題" } }
      expect(foreign.reload.title).to eq("新題")
      expect(response).to redirect_to(dashboard_path(foreign))
    end

    it "re-renders edit on invalid input" do
      dashboard = create(:dashboard, user: user)
      patch dashboard_path(dashboard), params: { dashboard: { title: "" } }
      expect(response).to have_http_status(:unprocessable_content)
    end
  end

  describe "DELETE /dashboards/:id" do
    before { login_as(user) }

    it "destroys the dashboard and its widgets" do
      dashboard = create(:dashboard, user: user)
      create(:widget, dashboard: dashboard)

      expect {
        delete dashboard_path(dashboard)
      }.to change(Dashboard, :count).by(-1).and change(Widget, :count).by(-1)

      expect(response).to redirect_to(dashboards_path)
    end
  end
end
