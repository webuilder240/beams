require "rails_helper"

# 組織フルオープン（計画書 §4.9 / トピック13）。
# ログイン済みユーザーは他ユーザーが作成したクエリ・ダッシュボードを
# 閲覧・編集・削除できる。所有者は記録するが制限には使わない。
RSpec.describe "Sharing (組織フルオープン)", type: :request do
  let(:owner) { create(:user, :member, password: "password") }
  let(:other) { create(:user, :member, password: "password") }
  let(:connection) { create(:bigquery_connection) }

  def login_as(who, password: "password")
    post session_path, params: { email: who.email, password: password }
  end

  describe "Query" do
    let!(:query) { create(:query, user: owner, title: "Owner Query") }

    context "別ユーザーでログイン中" do
      before { login_as(other) }

      it "他ユーザーのクエリを閲覧できる" do
        get query_path(query)

        expect(response).to have_http_status(:ok)
        expect(response.body).to include("Owner Query")
      end

      it "他ユーザーのクエリを編集できる" do
        patch query_path(query), params: {
          query: { title: "Edited By Other", sql_body: "SELECT 2", bigquery_connection_id: connection.id }
        }

        expect(response).to redirect_to(query_path(query))
        expect(query.reload.title).to eq("Edited By Other")
      end

      it "他ユーザーのクエリを削除できる" do
        delete query_path(query)

        expect(response).to redirect_to(queries_path)
        expect(Query.exists?(query.id)).to be(false)
      end
    end

    context "未ログイン" do
      before { create(:user) } # 初回セットアップ誘導を回避

      it "詳細はログインへリダイレクトされる" do
        get query_path(query)

        expect(response).to redirect_to(new_session_path)
      end
    end
  end

  describe "Dashboard" do
    let!(:dashboard) { create(:dashboard, user: owner, title: "Owner Dashboard") }

    context "別ユーザーでログイン中" do
      before { login_as(other) }

      it "他ユーザーのダッシュボードを閲覧できる" do
        get dashboard_path(dashboard)

        expect(response).to have_http_status(:ok)
        expect(response.body).to include("Owner Dashboard")
      end

      it "他ユーザーのダッシュボードを編集できる" do
        patch dashboard_path(dashboard), params: {
          dashboard: { title: "Edited By Other" }
        }

        expect(response).to redirect_to(dashboard_path(dashboard))
        expect(dashboard.reload.title).to eq("Edited By Other")
      end

      it "他ユーザーのダッシュボードを削除できる" do
        delete dashboard_path(dashboard)

        expect(response).to redirect_to(dashboards_path)
        expect(Dashboard.exists?(dashboard.id)).to be(false)
      end
    end

    context "未ログイン" do
      before { create(:user) } # 初回セットアップ誘導を回避

      it "詳細はログインへリダイレクトされる" do
        get dashboard_path(dashboard)

        expect(response).to redirect_to(new_session_path)
      end
    end
  end
end
