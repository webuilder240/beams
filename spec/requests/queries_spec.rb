require "rails_helper"

RSpec.describe "Queries", type: :request do
  let(:user) { create(:user, :member, password: "password") }
  let(:other_user) { create(:user, :member, password: "password") }
  let(:connection) { create(:bigquery_connection) }

  def login_as(who, password: "password")
    post session_path, params: { email: who.email, password: password }
  end

  describe "access control (unauthenticated rejected)" do
    it "redirects to login" do
      create(:user) # 初回セットアップ誘導を回避
      get queries_path
      expect(response).to redirect_to(new_session_path)
    end
  end

  context "as a logged-in user" do
    before { login_as(user) }

    describe "GET /queries" do
      it "lists all users' queries in updated_at desc order (org full-open §4.9)" do
        old = create(:query, user: user, title: "古い", updated_at: 2.days.ago)
        recent = create(:query, user: user, title: "新しい", updated_at: 1.hour.ago)
        create(:query, user: other_user, title: "他人のクエリ")

        get queries_path
        expect(response).to have_http_status(:ok)
        expect(response.body).to include("新しい")
        expect(response.body).to include("古い")
        # 全ユーザーのクエリが見える（§4.9）
        expect(response.body).to include("他人のクエリ")
        expect(response.body.index("新しい")).to be < response.body.index("古い")
      end

      it "filters by title with ?q= (partial match)" do
        create(:query, user: user, title: "売上集計")
        create(:query, user: user, title: "ユーザー一覧")

        get queries_path(q: "売上")
        expect(response.body).to include("売上集計")
        expect(response.body).not_to include("ユーザー一覧")
      end

      it "filters by SQL body with ?q= (partial match, トピック21)" do
        create(:query, user: user, title: "無題クエリA", sql_body: "SELECT user_id FROM events")
        create(:query, user: user, title: "無題クエリB", sql_body: "SELECT name FROM products")

        get queries_path(q: "user_id")
        expect(response.body).to include("無題クエリA")
        expect(response.body).not_to include("無題クエリB")
      end
    end

    describe "GET /queries/new" do
      it "renders the new form" do
        connection
        get new_query_path
        expect(response).to have_http_status(:ok)
      end
    end

    describe "POST /queries" do
      it "creates a query owned by the current user" do
        expect {
          post queries_path, params: {
            query: { title: "新規", sql_body: "SELECT 1", bigquery_connection_id: connection.id }
          }
        }.to change(user.queries, :count).by(1)
        created = user.queries.find_by(title: "新規")
        expect(created.sql_body).to eq("SELECT 1")
        expect(created.bigquery_connection).to eq(connection)
        expect(response).to redirect_to(query_path(created))
      end

      it "ignores user_id in params (owner is forced to current_user)" do
        post queries_path, params: {
          query: { title: "強制所有者", sql_body: "SELECT 1", bigquery_connection_id: connection.id, user_id: other_user.id }
        }
        created = Query.find_by(title: "強制所有者")
        expect(created.user).to eq(user)
      end

      it "re-renders on invalid input" do
        expect {
          post queries_path, params: {
            query: { title: "", sql_body: "", bigquery_connection_id: connection.id }
          }
        }.not_to change(Query, :count)
        expect(response).to have_http_status(:unprocessable_content)
      end
    end

    describe "GET /queries/:id" do
      it "shows the current user's query" do
        query = create(:query, user: user, title: "詳細クエリ")
        get query_path(query)
        expect(response).to have_http_status(:ok)
        expect(response.body).to include("詳細クエリ")
      end

      it "shows another user's query (org full-open §4.9)" do
        query = create(:query, user: other_user, title: "他人のクエリ詳細")
        get query_path(query)
        expect(response).to have_http_status(:ok)
        expect(response.body).to include("他人のクエリ詳細")
      end

      it "renders the parameter form for a parameterized query" do
        query = create(:query, user: user, sql_body: "SELECT {{ user_id:number }}")
        get query_path(query)
        expect(response.body).to include("パラメータ")
        expect(response.body).to include("query_params[user_id]")
      end

      it "does not render the parameter form when the query has no parameters" do
        query = create(:query, user: user, sql_body: "SELECT 1")
        get query_path(query)
        expect(response.body).not_to include("query_params[")
      end

      it "rejects execution when a required parameter value is blank" do
        query = create(:query, user: user, sql_body: "SELECT {{ a }}, {{ b }}")
        get query_path(query), params: { query_params: { a: "1", b: "" } }
        expect(response.body).to include("未入力のパラメータがあります")
        expect(response.body).to include("b")
      end

      it "ignores parameter names that are not defined on the query (whitelist)" do
        query = create(:query, user: user, sql_body: "SELECT {{ a }}")
        get query_path(query), params: { query_params: { a: "1", evil: "DROP TABLE" } }
        expect(response.body).to include("パラメータを受け付けました")
      end

      it "accepts when all required parameters are present" do
        query = create(:query, user: user, sql_body: "SELECT {{ a }}, {{ b }}")
        get query_path(query), params: { query_params: { a: "1", b: "2" } }
        expect(response.body).to include("パラメータを受け付けました")
      end

      describe "execution history (トピック17)" do
        it "renders the most recent executions newest-first with a result-display link" do
          query = create(:query, user: user, sql_body: "SELECT 1")
          older = create(:query_execution, :succeeded, query: query, created_at: 2.hours.ago,
                         result_row_count: 1)
          older.store_result([ { "name" => "n", "type" => "INTEGER" } ], [ [ 7 ] ])
          older.save!
          newer = create(:query_execution, :failed, query: query, created_at: 1.hour.ago,
                         error_message: "boom history")

          get query_path(query)

          expect(response).to have_http_status(:ok)
          # 新しい順で並ぶ（failed が succeeded より前）。各行は dom_id で識別。
          expect(response.body.index("id=\"#{ActionView::RecordIdentifier.dom_id(newer)}\""))
            .to be < response.body.index("id=\"#{ActionView::RecordIdentifier.dom_id(older)}\"")
          expect(response.body).to include("boom history")
          # 成功実行には結果再表示リンクが出る。
          expect(response.body).to include(query_execution_path(query, older))
        end

        it "initially renders the latest succeeded result even when a newer execution failed" do
          query = create(:query, user: user, sql_body: "SELECT 1")
          succeeded = create(:query_execution, :succeeded, query: query,
                             created_at: 2.hours.ago, result_row_count: 1)
          succeeded.store_result([ { "name" => "n", "type" => "INTEGER" } ], [ [ 42 ] ])
          succeeded.save!
          create(:query_execution, :failed, query: query, created_at: 1.hour.ago,
                 error_message: "later failure")

          get query_path(query)

          # query_result エリアの初期描画は最新の成功結果を優先する
          expect(response.body).to include("42")
        end
      end
    end

    describe "GET /queries/:id/edit" do
      it "renders the edit form for the current user's query" do
        query = create(:query, user: user, sql_body: "SELECT 42")
        get edit_query_path(query)
        expect(response).to have_http_status(:ok)
        expect(response.body).to include("SELECT 42")
      end
    end

    describe "PATCH /queries/:id" do
      it "updates the current user's query" do
        query = create(:query, user: user)
        patch query_path(query), params: {
          query: { title: "更新後", sql_body: "SELECT 2", bigquery_connection_id: connection.id }
        }
        expect(response).to redirect_to(query_path(query))
        expect(query.reload.title).to eq("更新後")
        expect(query.sql_body).to eq("SELECT 2")
      end

      it "re-renders on invalid input" do
        query = create(:query, user: user)
        patch query_path(query), params: { query: { title: "" } }
        expect(response).to have_http_status(:unprocessable_content)
      end

      it "updates another user's query (org full-open §4.9)" do
        query = create(:query, user: other_user)
        patch query_path(query), params: {
          query: { title: "更新", sql_body: "SELECT 9", bigquery_connection_id: connection.id }
        }
        expect(response).to redirect_to(query_path(query))
        expect(query.reload.title).to eq("更新")
      end
    end

    describe "DELETE /queries/:id" do
      it "deletes the current user's query" do
        query = create(:query, user: user)
        expect {
          delete query_path(query)
        }.to change(user.queries, :count).by(-1)
        expect(response).to redirect_to(queries_path)
      end

      it "deletes another user's query (org full-open §4.9)" do
        query = create(:query, user: other_user)
        expect {
          delete query_path(query)
        }.to change(Query, :count).by(-1)
        expect(response).to redirect_to(queries_path)
      end
    end
  end
end
