require "rails_helper"

RSpec.describe "WidgetOrders", type: :request do
  let(:user) { create(:user, :member, password: "password") }
  let(:dashboard) { create(:dashboard, user: user) }
  let(:query) { create(:query, user: user) }

  def login_as(who, password: "password")
    post session_path, params: { email: who.email, password: password }
  end

  describe "PATCH /dashboards/:dashboard_id/widget_order" do
    let!(:w1) { create(:widget, dashboard: dashboard, query: query, position: 0) }
    let!(:w2) { create(:widget, dashboard: dashboard, query: query, position: 1) }
    let!(:w3) { create(:widget, dashboard: dashboard, query: query, position: 2) }

    context "when authenticated" do
      before { login_as(user) }

      it "(a) reorders widgets and responds with turbo stream" do
        patch dashboard_widget_order_path(dashboard),
              params: { widget_ids: [ w3.id, w1.id, w2.id ] },
              headers: { "Accept" => "text/vnd.turbo-stream.html" }

        expect(response).to have_http_status(:ok)
        expect(response.media_type).to eq("text/vnd.turbo-stream.html")
        expect(w3.reload.position).to eq(0)
        expect(w1.reload.position).to eq(1)
        expect(w2.reload.position).to eq(2)
      end

      it "(a) redirects to dashboard on HTML fallback" do
        patch dashboard_widget_order_path(dashboard),
              params: { widget_ids: [ w2.id, w1.id, w3.id ] }

        expect(response).to redirect_to(dashboard_path(dashboard))
      end

      it "(c) handles empty widget_ids gracefully (returns 2xx, positions unchanged)" do
        original_positions = [ w1.reload.position, w2.reload.position, w3.reload.position ]

        patch dashboard_widget_order_path(dashboard),
              params: { widget_ids: [] },
              headers: { "Accept" => "text/vnd.turbo-stream.html" }

        expect(response).to have_http_status(:ok)
        expect([ w1.reload.position, w2.reload.position, w3.reload.position ])
          .to eq(original_positions)
      end

      it "(c) handles missing widget_ids param gracefully (returns 2xx)" do
        patch dashboard_widget_order_path(dashboard),
              headers: { "Accept" => "text/vnd.turbo-stream.html" }

        expect(response).to have_http_status(:ok)
      end

      it "(d) ignores widget IDs from other dashboards" do
        other_dashboard = create(:dashboard, user: user)
        other_widget = create(:widget, dashboard: other_dashboard, query: query, position: 0)

        patch dashboard_widget_order_path(dashboard),
              params: { widget_ids: [ other_widget.id, w1.id, w2.id ] },
              headers: { "Accept" => "text/vnd.turbo-stream.html" }

        expect(response).to have_http_status(:ok)
        expect(other_widget.reload.position).to eq(0)
      end
    end

    it "(b) redirects unauthenticated requests to login" do
      patch dashboard_widget_order_path(dashboard),
            params: { widget_ids: [ w1.id ] }

      expect(response).to redirect_to(new_session_path)
    end
  end
end
