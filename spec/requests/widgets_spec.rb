require "rails_helper"

RSpec.describe "Widgets", type: :request do
  let(:user) { create(:user, :member, password: "password") }
  let(:dashboard) { create(:dashboard, user: user) }
  let(:query) { create(:query, user: user) }

  def login_as(who, password: "password")
    post session_path, params: { email: who.email, password: password }
  end

  describe "authentication" do
    before { create(:user) }

    it "redirects POST create to login when unauthenticated" do
      post dashboard_widgets_path(dashboard), params: { widget: { query_id: query.id } }
      expect(response).to redirect_to(new_session_path)
    end
  end

  describe "POST /dashboards/:dashboard_id/widgets" do
    before { login_as(user) }

    it "appends a widget at the tail (max position + 1)" do
      create(:widget, dashboard: dashboard, query: query, position: 0)

      expect {
        post dashboard_widgets_path(dashboard),
             params: { widget: { query_id: query.id, column_span: 2 } }
      }.to change { dashboard.widgets.count }.by(1)

      widget = dashboard.widgets.order(:position).last
      expect(widget.position).to eq(1)
      expect(widget.column_span).to eq(2)
    end

    it "creates the first widget at position 0" do
      post dashboard_widgets_path(dashboard), params: { widget: { query_id: query.id } }
      expect(dashboard.widgets.order(:position).first.position).to eq(0)
    end

    it "responds with a turbo stream" do
      post dashboard_widgets_path(dashboard),
           params: { widget: { query_id: query.id } },
           headers: { "Accept" => "text/vnd.turbo-stream.html" }
      expect(response.media_type).to eq("text/vnd.turbo-stream.html")
    end
  end

  describe "DELETE /dashboards/:dashboard_id/widgets/:id" do
    before { login_as(user) }

    it "destroys the widget" do
      widget = create(:widget, dashboard: dashboard, query: query)
      expect {
        delete dashboard_widget_path(dashboard, widget)
      }.to change(Widget, :count).by(-1)
    end
  end

  describe "PATCH /dashboards/:dashboard_id/widgets/reorder" do
    before { login_as(user) }

    let!(:w1) { create(:widget, dashboard: dashboard, query: query, position: 0) }
    let!(:w2) { create(:widget, dashboard: dashboard, query: query, position: 1) }
    let!(:w3) { create(:widget, dashboard: dashboard, query: query, position: 2) }

    it "reorders widgets and responds with turbo stream" do
      patch reorder_dashboard_widgets_path(dashboard),
            params: { widget_ids: [ w3.id, w1.id, w2.id ] },
            headers: { "Accept" => "text/vnd.turbo-stream.html" }

      expect(response).to have_http_status(:ok)
      expect(response.media_type).to eq("text/vnd.turbo-stream.html")
      expect(w3.reload.position).to eq(0)
      expect(w1.reload.position).to eq(1)
      expect(w2.reload.position).to eq(2)
    end

    it "redirects to dashboard when request is HTML (fallback)" do
      patch reorder_dashboard_widgets_path(dashboard),
            params: { widget_ids: [ w2.id, w1.id, w3.id ] }

      expect(response).to redirect_to(dashboard_path(dashboard))
    end

    it "redirects unauthenticated requests to login" do
      # ログアウト状態でリクエスト
      delete session_path
      patch reorder_dashboard_widgets_path(dashboard),
            params: { widget_ids: [ w1.id ] }

      expect(response).to redirect_to(new_session_path)
    end

    it "handles missing widget_ids gracefully (empty array)" do
      patch reorder_dashboard_widgets_path(dashboard),
            params: { widget_ids: [] },
            headers: { "Accept" => "text/vnd.turbo-stream.html" }

      expect(response).to have_http_status(:ok)
    end

    it "ignores widget IDs from other dashboards" do
      other_dashboard = create(:dashboard, user: user)
      other_widget = create(:widget, dashboard: other_dashboard, query: query, position: 0)

      patch reorder_dashboard_widgets_path(dashboard),
            params: { widget_ids: [ other_widget.id, w1.id, w2.id ] },
            headers: { "Accept" => "text/vnd.turbo-stream.html" }

      expect(response).to have_http_status(:ok)
      # 他ダッシュボードのウィジェットの position は変わらない
      expect(other_widget.reload.position).to eq(0)
    end
  end
end
