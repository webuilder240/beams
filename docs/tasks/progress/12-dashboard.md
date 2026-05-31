# 作業進捗ログ — トピック12: ダッシュボード

> タスク `docs/tasks/12-dashboard.md` の作業ログ（時系列）。司令塔・Coder・Tester のアクションを記録。

- **ステータス**: 🔄進行中
- **担当**: Coder

## 司令塔メモ（着手時の判断・名称読み替え）

- **新規マイグレーション2件必要**: `dashboards` / `widgets` テーブル → **マイグレーション承認ゲート**（確認ドキュメント→人間承認→migrate）。1つの確認ドキュメントに両テーブルをまとめる。
- **名称読み替え（タスク doc の前提名が実装と異なる）**:
  - `QueryExecution#result_data` → 実装は **`QueryExecution#result`**（`{schema:, rows:}`、未保存 nil。topic-10）。
  - ウィジェットが表示する「クエリの最新結果」→ **`Query#latest_succeeded_execution`**（topic-10 実装済み）の `#result`。
  - ウィジェットのチャートは **`query.visualization`**（`has_one`、topic-11）の `display_mode` に従いテーブル/チャート描画。
- **未決事項の司令塔決定（doc の想定どおり採用）**:
  - ウィジェット内チャートは **`query_id` から `query.visualization` を特定**して topic-11 の描画を再利用。
  - `column_span` UI は **追加時に 1 か 2 を選ぶ `<select>`**。
  - 参照クエリに成功実行が無い場合は **「未実行」プレースホルダー**を表示。
- **権限方針**（計画書 §4.9）: ログインユーザーは**全ダッシュボードを閲覧・編集可**。`user_id` は所有者記録のみで閲覧/編集制限には使わない（topic-07/10 の owner-scoped とは異なる点に注意）。未ログインはログインへリダイレクト。

## 時系列ログ

### 2026-05-31

- **司令塔**: トピック11完了（Tester PASS）を受け、依存（11・03・07・10）充足済みのトピック12に着手。新規 Coder をアサイン。`dashboards`/`widgets` の2テーブルのマイグレーションが必要 → 承認ゲート。まず確認用ドキュメント作成を指示（承認まで `db:migrate` 禁止）。
- **Coder→司令塔**: 確認ドキュメント `migrations/12-dashboards-widgets-migration.md`（2テーブル統合）＋マイグレーション2件（`20260531150000_create_dashboards`・`20260531150001_create_widgets`、未実行）作成。論点4点（user_id NOT NULL / 複合index[dashboard_id,position]・position非unique / CASCADE はアプリ層 dependent / column_span はアプリ層 validation）を推奨付きで提起。既存 `Query#latest_succeeded_execution`・`QueryExecution#result`・`Query has_one :visualization` のシグネチャ確認。
- **司令塔→人間**: マイグレーション承認を依頼（司令塔レビュー済み、論点4点とも Coder 推奨に同意。特に position 非unique は move_up/down のスワップ中間状態で一時重複しうるため妥当）。
- **人間→司令塔**: ✅**承認・実行する**。`db:migrate` 実行を許可。
- **司令塔→Coder**: マイグレーション実行＋トピック12 本体（Dashboard/Widget モデル / DashboardsController CRUD / WidgetsController create/destroy/move_up/move_down / Turbo Frames ウィジェット一覧・並べ替え / 1〜2カラムグリッド / ウィジェット内 topic-11 チャート再利用 / 「未実行」プレースホルダー）を TDD で実装するよう指示。
