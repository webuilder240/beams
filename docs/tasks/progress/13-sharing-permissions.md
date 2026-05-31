# トピック13: 共有・権限（組織フルオープン） 進捗（時系列）

> ⚠️ 訂正記録: 本ファイルには一時、司令塔の運用ミスにより「削除は作成者/admin のみ・403」という**要件と逆の内容**と**捏造コミットハッシュ**を含む完了記録が書かれていた。要件ファイル `13-sharing-permissions.md` の正は「**組織フルオープン**: 全ログインユーザーが全クエリ・全ダッシュボードを閲覧・編集・削除でき、所有者制限コードを置かない」。以下は実コードに基づく正しい記録。

## 2026-05-31 着手〜完了

- 事前調査: カラムは `user_id`（`created_by` ではない）、`Query`/`Dashboard` とも `belongs_to :user`。**マイグレーション不要**。`DashboardsController` は既にフルオープン（`Dashboard.find`）。`QueriesController` のみ所有者スコープ（要件違反）だったため是正。
- Coder13b が TDD で実装（実在コミット `c0d4178`/`e137af0`/`aee76f3`）:
  - **Query フルオープン化**: `QueriesController#index` を `Query.title_matching(params[:q]).order(updated_at: :desc)`（全件）、`#set_query` を `Query.find(params[:id])` に変更。`create` は `current_user.queries.new`（所有者記録）維持。権限チェック/403 は不追加。
  - **所有者名表示**: queries/dashboards の index・show に所有者名（`user.email`）表示。
  - **共有 request spec**: `spec/requests/sharing_spec.rb`（A作成→B が show 200・update 成功（reload で変更確認）・destroy 成功（レコード消滅）を Query・Dashboard 両方で。未ログインは `new_session_path` リダイレクト）。
  - 既存 `queries_spec.rb`・system spec の「他人のクエリは404」前提をフルオープン前提に是正。
- 司令塔が要点を実検証（`grep` で 403/authorize/Pundit/deletable_by が app に皆無、set_query が `Query.find`、sharing_spec 8例 green）。
- Tester13b が独立検証で **PASS**（`db:test:prepare` 後 rspec 451/0、カバレッジ 98.5%、rubocop 0、brakeman 0、runner で B から A のリソース取得可を検算、コミット実在を `git cat-file` で確認）。

## 要件チェック
- フルオープン閲覧/編集/削除 ✅ / 所有者記録のみ（制限に使わない）✅ / 所有者名表示 ✅ / 制限コード不在（Pundit/CanCanCan/403 なし）✅ / 未ログインリダイレクト ✅
