require "rails_helper"

RSpec.describe "Visualizations", type: :request do
  let(:user) { create(:user, :member, password: "password") }
  let(:other_user) { create(:user, :member, password: "password") }
  let(:query) { create(:query, user: user) }

  def login_as(who, password: "password")
    post session_path, params: { email: who.email, password: password }
  end

  describe "GET /queries/:query_id/visualization" do
    it "redirects unauthenticated requests to login" do
      create(:user) # セットアップ誘導回避
      get query_visualization_path(query)
      expect(response).to redirect_to(new_session_path)
    end

    it "returns 404 for another user's query" do
      login_as(user)
      foreign = create(:query, user: other_user)
      get query_visualization_path(foreign)
      expect(response).to have_http_status(:not_found)
    end

    context "as the owner" do
      before { login_as(user) }

      it "renders the visualization page" do
        get query_visualization_path(query)
        expect(response).to have_http_status(:ok)
      end

      it "builds a default visualization when none exists" do
        get query_visualization_path(query)
        expect(response.body).to include("チャート").or include("テーブル")
      end
    end
  end

  describe "PATCH /queries/:query_id/visualization" do
    it "redirects unauthenticated requests to login" do
      create(:user)
      patch query_visualization_path(query), params: { visualization: { chart_type: "bar" } }
      expect(response).to redirect_to(new_session_path)
    end

    it "returns 404 for another user's query" do
      login_as(user)
      foreign = create(:query, user: other_user)
      patch query_visualization_path(foreign), params: { visualization: { chart_type: "bar" } }
      expect(response).to have_http_status(:not_found)
    end

    context "as the owner" do
      before { login_as(user) }

      it "creates a visualization on first update (upsert)" do
        expect {
          patch query_visualization_path(query),
                params: { visualization: { chart_type: "bar", display_mode: "chart" } }
        }.to change(Visualization, :count).by(1)

        expect(query.reload.visualization.chart_type).to eq("bar")
        expect(query.visualization.display_mode).to eq("chart")
      end

      it "updates an existing visualization without creating a new one" do
        create(:visualization, query: query, chart_type: "line")

        expect {
          patch query_visualization_path(query),
                params: { visualization: { chart_type: "pie" } }
        }.not_to change(Visualization, :count)

        expect(query.reload.visualization.chart_type).to eq("pie")
      end

      it "saves axis settings including y_columns array" do
        patch query_visualization_path(query),
              params: { visualization: { chart_type: "line", x_column: "day", y_columns: %w[a b] } }

        viz = query.reload.visualization
        expect(viz.x_column).to eq("day")
        expect(viz.y_columns).to eq(%w[a b])
      end

      it "saves counter settings" do
        patch query_visualization_path(query),
              params: { visualization: { chart_type: "counter", counter_column: "amount", counter_aggregation: "avg" } }

        viz = query.reload.visualization
        expect(viz.chart_type).to eq("counter")
        expect(viz.counter_column).to eq("amount")
        expect(viz.counter_aggregation).to eq("avg")
      end

      it "re-renders the page on invalid input" do
        patch query_visualization_path(query),
              params: { visualization: { chart_type: "invalid" } }
        expect(response).to have_http_status(:unprocessable_content)
      end
    end
  end
end
