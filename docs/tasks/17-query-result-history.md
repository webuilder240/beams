# トピック17: クエリ実行結果のレンダリング修正・実行履歴表示

> クエリ詳細ページで「BigQuery から取得した結果が表示されない」事象を解消し、過去の実行履歴を一覧表示して各実行の結果テーブルを再表示できるようにする。

- **ステータス**: 完了
- **依存**: [[10-query-execution]]（`QueryExecution` モデル・非同期実行・Turbo Streams）/ [[07-query-editor]]（クエリ詳細ページ）
- **関連計画書**: §4.6（非同期実行・結果保存）, §6.1-6.3

## 背景・事象

クエリ詳細ページ（`/queries/:id`）でクエリを実行した際、**BigQuery から取得した結果が画面に表示されない**ケースがある。また、**過去の実行結果を後から見返す手段が無い**。

### 現状の挙動（コード調査結果）

- `QueriesController#show` は直近 1 件のみを読み込む:
  `@latest_execution = @query.query_executions.order(created_at: :desc).first`
- 結果エリアは `app/views/query_executions/_state.html.erb` が `@latest_execution` の状態で出し分け（未実行 / 実行中 / 失敗 / 成功＝`_result`）。
- 実行完了時は `QueryExecutionJob.broadcast_result` が Turbo Streams（SolidCable）で `target: "query_result"` を `_result` / `_error` に置換。詳細ページは `turbo_stream_from @query` で購読。
- 各 `QueryExecution` は**自分の `result_blob`（gzip+JSON の表示用先頭N行）を個別に保持**しており（`store_result` / `result`）、DB 上は実行ごとの結果が残る。CSV も `storage/csv/<execution.id>.csv.gz` と実行 ID で分かれて保存される。
- にもかかわらず UI は「最新 1 件」しか描画せず、**履歴一覧・過去結果の再表示ルートが存在しない**（ルートは `executions#create` と `latest/csv` のみ）。

### 想定される「結果が表示されない」原因（要切り分け）

1. 実行直後のライブ更新が届かない: SolidCable の購読/ブロードキャストの不整合、または `turbo_stream_from` の購読開始前にブロードキャストが発火するレース。
2. リロードしても見当たらない: 新しい実行を始めると `query_result` が置き換わり、前回の成功結果が画面から消える（履歴 UI が無いため遡れない）。
3. `@latest_execution` が失敗/実行中だと成功結果が隠れる。

→ 本タスクは **(a) 実行履歴を恒久的に描画する** ことで結果を「見失わない」状態にし、あわせて **(b) ライブ描画の不具合を切り分けて修正** する。

## ゴール（完了の定義）

- クエリ詳細ページに**実行履歴一覧**が表示される（直近 N 件・新しい順、status / 開始・終了時刻 / 所要時間 / 行数 / 切り詰めフラグ）
- 履歴の各実行から、その実行が保持する**結果テーブル（`result_blob` から復元）を再表示**できる
- クエリ実行直後、結果（または失敗）が `query_result` に描画され、かつ履歴一覧にも反映される（Turbo Streams のライブ更新が検証済み）
- 上記を担保する RSpec（モデル / リクエスト / System / ブロードキャスト）が green
- 既存テストを壊さず、SimpleCov 85% 以上を維持する

## 前提・参照

- `QueryExecution`（`app/models/query_execution.rb`）: `belongs_to :query`、enum `status`（pending/running/succeeded/failed）、`store_result` / `result`、カラム `started_at` `finished_at` `result_row_count` `result_truncated` `result_blob` `error_message`。
  - モデル冒頭コメントの「結果は最新成功1件のみ保持（上書き・履歴なし）」は実装（実行ごとに `result_blob` を保持）と齟齬があるため**コメントを実態に合わせて修正**する。
- ビュー: `app/views/query_executions/_state.html.erb`（ディスパッチャ）/ `_result.html.erb` / `_running.html.erb` / `_error.html.erb`。`_result` は `execution` を受け取り `result_blob` から復元して描画する（再利用可能）。
- ジョブ/ブロードキャスト: `app/jobs/query_execution_job.rb` の `self.broadcast_result`。
- ルート: `config/routes.rb` の `resources :executions, only: [ :create ], module: "queries"`（`latest/csv` をネスト）。
- 表示ページ: `app/views/queries/show.html.erb`（`turbo_stream_from @query` と `render "query_executions/state"` を含む）。

## タスク

### 1. ライブ描画の切り分け・修正

- [x] 実行→結果のライブ更新を再現確認し、原因を特定する（SolidCable 購読、`turbo_stream_from @query` と `broadcast_replace_to(execution.query, ...)` のストリーム名一致、購読前ブロードキャストのレース）
  - 受け入れ条件: 原因を `docs/tasks/progress/17-query-result-history.md` に記録する
- [x] 必要に応じて修正（例: `show` で初期描画する `@latest_execution` の選択を「最新の成功実行」優先にする／実行作成時に即 `running` を `query_result` へ反映する経路の確認）
  - 受け入れ条件: 実行直後に結果が `query_result` に表示される（System Spec で確認、下記）

### 2. 実行履歴の表示（過去結果のRender）

- [x] `QueryExecution` に履歴取得用スコープと表示補助を追加（`app/models/query_execution.rb`）— 例: `scope :recent, -> { order(created_at: :desc) }`、`#duration`（started/finished から秒）、`#succeeded_with_result?`。冒頭コメントの「履歴なし」記述を修正
  - 受け入れ条件: `QueryExecution.recent` が新しい順、`#duration` が正しい秒数を返す（モデルスペック green）
- [x] `QueriesController#show` で履歴を読み込む（`@executions = @query.query_executions.recent.limit(N)`、N は 20 目安）
  - 受け入れ条件: 詳細ページに直近 N 件が新しい順で渡る（リクエストスペック）
- [x] 実行履歴一覧の partial を追加（`app/views/query_executions/_history.html.erb`）— status バッジ / 開始・終了時刻（`l(..., format: :short)`）/ 所要時間 / 行数 / `result_truncated` 表示 / 「結果を表示」リンク / 成功実行の CSV リンク。`queries/show` に差し込む
  - 受け入れ条件: 複数回実行したクエリの詳細ページに履歴行が並ぶ（System Spec `rack_test`）
- [x] 過去実行の結果を再表示するアクションを追加（`Queries::ExecutionsController#show`、ルートに `:show` を追加）— `@query.query_executions.find(params[:id])` を `_state`（または `_result`）で描画。所有者スコープ外は 404
  - 受け入れ条件: `GET /queries/:query_id/executions/:id` が当該実行の結果テーブル（`result_blob` 復元）を返す（リクエストスペック）。他ユーザーのクエリ配下は 404

### 3. 履歴のライブ追記（任意・推奨）

- [x] ジョブ完了時に `query_result` の置換に加え、履歴一覧へ新規行を `turbo_stream.prepend` する（`broadcast_result` を拡張、または history 用ターゲットを追加）
  - 受け入れ条件: 実行完了時、リロードせずに履歴一覧の先頭へ行が追加される（ブロードキャストスペック）

### 4. 過去実行の CSV（要確認・任意）

- [x] 過去実行の CSV ダウンロード可否を確認する。現状ルートは `latest/csv` のみ。各実行の CSV は `storage/csv/<id>.csv.gz` に存在するため、必要なら `GET /queries/:query_id/executions/:id/csv` を追加
  - 受け入れ条件: 仕様判断を `未決事項` に記録。実装する場合はリクエストスペックで配信を確認

### 5. RSpec（TDD）

- [x] モデルスペック（`spec/models/query_execution_spec.rb`）: `recent` 順序 / `duration` / `result` の blob 復元 / `succeeded_with_result?`
  - 受け入れ条件: 全 green
- [x] リクエストスペック（`spec/requests/queries/executions_spec.rb` 等）: `executions#show` が成功実行の結果を返す / 失敗・実行中の状態表示 / 他ユーザーのクエリ配下は 404
  - 受け入れ条件: 全 green
- [x] System Spec（`spec/system/`・`rack_test`）: 複数回実行 → 詳細ページに履歴が並ぶ → 過去実行の「結果を表示」で結果テーブルが描画される
  - 受け入れ条件: 全 green
- [x] ブロードキャストスペック（既存の実行ブロードキャストスペックを拡張）: ジョブ完了で `query_result` 置換（＋履歴 prepend を実装した場合はその検証）
  - 受け入れ条件: 全 green

## 動作確認

- [ ] `bin/dev` で起動し、パラメータ無しクエリを 2〜3 回実行 → 詳細ページに履歴が新しい順で並ぶ（**未実施**: ブラウザ手動確認は未実施。System Spec `rack_test` で複数実行→履歴 newest-first を自動検証済み）
- [ ] 実行直後、リロードせずに結果テーブルが `query_result` に表示される（**未実施**: ライブ更新（WebSocket）は JS 依存のためブラウザ手動確認は未実施。ブロードキャストスペックで `query_result` 置換＋履歴 prepend を自動検証済み）
- [x] 履歴の過去行から「結果を表示」を押すと、その実行の結果テーブルが再描画される（System Spec `rack_test` で検証）
- [x] 失敗実行はエラーメッセージ付きで履歴に残る（System Spec `rack_test` で検証）
- [x] `bundle exec rspec` がグリーン、SimpleCov 85% 以上（507 examples / 0 failures / 98.88%）
- [x] `bin/rubocop` がエラーなし（145 files, no offenses）

## 未決事項・質問

### 確定済み（司令塔がボスに確認）

- **履歴の保持件数**: 表示は直近 **20 件**・新しい順。**剪定なし（MVP）**。古い実行レコード/CSV の自動削除は実装しない。
- **過去実行ごとの CSV ダウンロード（タスク4）**: **提供しない**。既存の `latest/csv` ルートのみ維持。`GET /queries/:query_id/executions/:id/csv` は追加しない。履歴行の CSV リンクは最新の成功実行（`Query#latest_succeeded_execution`＝succeeded を created_at 降順で 1 件）のみに表示し、「latest」が最新の成功実行を指す挙動を確認済み。

### 将来課題（残す）

- 古い実行レコード/CSV（`storage/csv/<id>.csv.gz`）が実行ごとに増える点。件数・期間での剪定（クリーンアップ）方針は将来課題として未決。
- ライブ更新（SolidCable WebSocket 配送）の本番/開発環境での実配信確認。ストリーム名一致・ブロードキャスト経路はスペックで担保済みだが、WebSocket 実配送の手動/JS 確認は本タスク範囲外。
