# 作業進捗ログ — トピック12: ダッシュボード

> タスク `docs/tasks/12-dashboard.md` の作業ログ（時系列）。司令塔・Coder・Tester のアクションを記録。

- **ステータス**: ✅完了（Tester PASS）
- **担当**: Coder / Tester

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
- **Coder**: マイグレーション実行（`db:migrate` → `db:test:prepare`）。`db/schema.rb` が `version: 20260531150001` に更新、`dashboards`/`widgets` 反映を確認。
- **Coder**: 本体を TDD（Red→Green→Refactor）で実装。
  - **Dashboard モデル**（`app/models/dashboard.rb`）: `belongs_to :user` / `has_many :widgets, dependent: :destroy` / `validates :title, presence, length<=255` / `#ordered_widgets`（`widgets.order(:position)`）。factory・spec。
  - **Widget モデル**（`app/models/widget.rb`）: `belongs_to :dashboard`/`:query` / `validates :position`(整数・0以上)・`:column_span`(in [1,2]) / `#display_title`（`title_override` 空なら `query.title`）/ 並べ替えを **モデルメソッド** `#move_up!`/`#move_down!`（隣接スワップ・端は no-op、`*Service` 禁止に適合）として実装。factory・spec。
  - **DashboardsController**: index(全件 `updated_at DESC`)/show/new/create/edit/update/destroy。**組織フルオープン（§4.9）= owner-scope せず `Dashboard.find`**、`create`/`update` で `user=current_user`。未ログインはログインへ 302。
  - **WidgetsController**: create(末尾=max position+1)/destroy/move_up/move_down。各アクション Turbo Stream で `<turbo-frame id="widgets">` 再描画（共通パーシャル `_widgets_stream`）。
  - **ビュー**: dashboards index(空時「まだダッシュボードがありません」)/show(`turbo-frame#widgets`＋追加フォーム=クエリ`<select>`＋column_span 1/2 `<select>`)/new/edit/_form(エラー表示)、widgets `_widget`（`display_title`・最新結果テーブル/チャート・上へ/下へ/削除・`未実行` プレースホルダー）。1〜2カラムグリッドは show のインライン `<style>`（`.dashboard-grid` / `.widget-span-2`）。
  - **チャート再利用**: ウィジェットは `query.visualization&.display_mode == "chart"` のとき topic-11 の `visualizations/_chart` を、それ以外は `visualizations/_result_table` を render（helper `chart_config_for` 等を再利用）。
  - **System spec**（`spec/system/dashboards_spec.rb`）: rack_test で 空状態→作成→ウィジェット2追加→下へ並べ替え→リロード順序保持→ウィジェット削除→ダッシュボード削除で widget CASCADE。`未実行` プレースホルダー。バリデーションエラー。`js: true` でチャートウィジェットの canvas 描画を最小確認。
- **Coder→司令塔**: 本体実装完了。`bundle exec rspec` **425 examples, 0 failures**、SimpleCov **98.87%**（≥85）。`bin/rubocop` 0 offense、`bin/brakeman` 0 警告、`bin/importmap audit` 0。Tester へ引き継ぎ依頼。

### 2026-05-31（Tester 独立QA）

- **司令塔→Tester**: 報告を鵜呑みにせず独立 QA を指示（09 の教訓）。12観点。重点: **`move_up!`/`move_down!` を `bin/rails runner` で検算**、**権限が誤って owner-scope されていないか**（topic-07/10 とは逆＝組織フルオープン §4.9）。
- **Tester→司令塔**: **総合判定 PASS**。全12観点 ✅。
  - **move_up!/move_down! runner 検算**: 初期 pos[0,1,2] の3ウィジェットで中央 move_up!→順序入替（pos スワップ）、`Dashboard.find` 再読込でも順序保持、先頭 move_up!＝no-op、末尾 move_down!＝no-op。`swap_with` は `transaction` 内・position 一意制約なしで中間状態も問題なし。
  - **権限（逆スコープ）確認**: `DashboardsController`/`WidgetsController` とも `Dashboard.find`（owner-scope なし）。`current_user.queries` は show のウィジェット追加 select 用途のみ（誤保護ではない）。create/update で `user=current_user`。未ログイン302。**他ユーザーのダッシュボードを show/update できることを request spec で明示検証**（§4.9 組織フルオープン）。
  - 独立再現: `rspec` **425/0**・SimpleCov **98.87%**・rubocop 0・brakeman 0・importmap 0。js チャート spec（canvas 検証）も green に含まれスキップなし。
  - **申し送り**: 重大なものなし。補足: js spec は chromium 前提のため CI で `npx playwright install chromium` 済みかインフラ確認推奨。
- **司令塔**: Tester PASS を受けトピック12を **✅完了** と判定。索引・本ログ・`12-dashboard.md`・`00-overview.md` を完了に更新、コミット。

#### ステータス: ✅完了（Tester PASS）
