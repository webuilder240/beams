# 進捗ログ: トピック17 クエリ実行結果のレンダリング修正・実行履歴表示

## 確定方針（司令塔がボスに確認済み）

1. **履歴の保持件数**: 表示は直近20件・新しい順。剪定なし（MVP）。古い実行レコード/CSVの自動削除は実装しない（将来課題として未決事項に残す）。
2. **過去実行ごとのCSVダウンロード（タスク4）**: 提供しない。既存の `latest/csv` ルートのみ維持。`GET /queries/:query_id/executions/:id/csv` は追加しない。履歴UIからは「結果テーブル再表示」のみ提供。
3. **履歴のライブ追記（タスク3）**: 実装する。ジョブ完了時に `query_result` の置換に加え、履歴一覧の先頭へ `turbo_stream.prepend` で新規行を追加する。ブロードキャストスペックで検証する。

## ライブ描画不具合の原因切り分け（タスク1）

既存コードを実読して切り分けた結果:

- **ストリーム名の一致**: `show.html.erb` は `turbo_stream_from @query` で購読し、`QueryExecutionJob.broadcast_result` は `Turbo::StreamsChannel.broadcast_replace_to(execution.query, target: "query_result", ...)` でブロードキャストする。購読チャネル名（`@query`）とブロードキャスト先（`execution.query`）は同一の `Query` レコードなので **ストリーム名は一致している**。ブロードキャストスペック（`spec/jobs/query_execution_broadcast_spec.rb`）でも検証済み。
- **「結果が表示されない」体感の主因（コード上の確定原因）**:
  `QueriesController#show` が初期描画する `@latest_execution` を
  `@query.query_executions.order(created_at: :desc).first`（＝単純に最新1件）で選んでいる。
  そのため、成功実行のあとに新しい実行（running/failed）を始めると、リロード時の初期描画が
  running/failed になり、**直前の成功結果が画面から消える**（背景・事象の (2)(3) に該当）。
  さらに過去の成功結果を遡る履歴UI・ルートが存在しないため「見失う」。
- **対処**:
  1. 履歴一覧を恒久描画（タスク2）して結果を見失わない状態にする。
  2. `show` の初期結果描画を「最新の成功実行を優先」に変更し、無ければ最新実行で状態表示する。
  3. ライブ追記（タスク3）で実行完了時に履歴へ prepend する。
- **SolidCable 設定起因かどうか**: ストリーム名は一致しており、ブロードキャスト経路はスペックで検証可能。
  本番 SolidCable の WebSocket 配送そのものは JS/WebSocket 依存のため rack_test では検証せず、
  ブロードキャストスペック（`have_broadcasted_to` / 実体スタブ）で担保する。根本が SolidCable 設定に
  ある可能性は本タスク範囲外として未決事項に残す。

## 作業ログ（時系列）

1. 既存実装を実読（model/job/routes/controllers/views/specs/locale）。
2. ライブ描画原因を切り分け（上記「ライブ描画不具合の原因切り分け」参照）。ストリーム名は一致。
   主因は `show` の初期描画が単純な最新1件で、成功後に新規実行を始めると成功結果が消える点。
3. TDD（model）: `recent` / `#duration` / `#succeeded_with_result?` のスペックを追加（Red）→
   `QueryExecution` に実装（scope + 2 メソッド）し冒頭コメントを実態に合わせ修正（Green）。
4. TDD（request: executions#show）: `spec/requests/queries/executions/show_spec.rb` を追加（Red）→
   ルートに `:show` 追加・`Queries::ExecutionsController#show` 実装（所有者スコープ・別クエリ/他人は 404・
   turbo_stream/html 両対応）（Green）。
5. TDD（request: queries#show 履歴）: `queries_spec.rb` に履歴系スペック追加（Red）→
   `QueriesController#show` で `@executions = recent.limit(20)`、初期描画は
   `latest_succeeded_execution || @executions.first`（最新成功優先）に変更（Green）。
   履歴 partial `_history.html.erb` / `_history_row.html.erb` を追加し `show` に差し込み。
6. TDD（broadcast 履歴 prepend）: `query_execution_broadcast_spec.rb` に prepend 検証追加（Red）→
   `broadcast_result` を拡張し `broadcast_prepend_to(target: "query_history_rows",
   partial: "query_executions/history_row")` を追加（Green）。
7. System Spec（rack_test）: 履歴一覧 newest-first・「結果を表示」再描画・失敗履歴の
   エラーメッセージ表示を `spec/system/query_execution_spec.rb` に追加（Green）。
8. locale: `config/locales/en.yml`（default locale）に `time.formats.short` を追加（`l(..., format: :short)` 用）。
9. タスク4（過去実行ごとの CSV）: **提供しない**判断（司令塔確定方針2）。`latest/csv` ルートのみ維持し、
   履歴行の CSV リンクは最新成功実行（`latest_succeeded_id == execution.id`）のみに表示。
   `Query#latest_succeeded_execution` は succeeded を created_at 降順で 1 件返す＝「latest」が
   最新の成功実行を指す挙動を確認（既存実装どおり）。
10. 全体: `bundle exec rspec` 507 examples / 0 failures / Line Coverage 98.88%。`bin/rubocop` no offenses。

## 新規マイグレーションの要否

**不要**。既存 `query_executions` の started_at/finished_at/result_row_count/result_truncated/
result_blob/error_message カラムのみで完結。スキーマ変更なし。

## 実テスト結果

- `bundle exec rspec`（全体）: `507 examples, 0 failures` / `Line Coverage: 98.88% (972 / 983)`
- `bin/rubocop`: `145 files inspected, no offenses detected`

## 追記: トピック13（組織フルオープン）整合のアクセス制御修正（ボス決定）

- **決定**: 過去結果の再表示（`executions#show`・読み取り）は**全ユーザー可**にフルオープンへ揃える。
  実行（`executions#create`・書き込み/課金）のみ**所有者スコープ**を維持。タスク冒頭の
  「他ユーザーのクエリ配下は404」はトピック13（§4.9）に合わせて上書き。
- **背景**: `QueriesController#show` は `Query.find`（フルオープン）で他人のクエリ詳細も閲覧でき
  履歴の「結果を表示」リンクを描画するが、`executions#show` が所有者スコープだと当該リンクが
  必ず 404 になる不整合があった。
- **修正**: `Queries::ExecutionsController` の before_action を分離。
  `set_query`（`current_user.queries.find`・owner）を `only: [ :create ]` に限定し、
  `show` 用に `set_query_full_open`（`Query.find`）を `only: [ :show ]` で追加。
  存在しない query_id / 当該クエリ配下に無い execution id は引き続き 404（RecordNotFound）。
- **TDD**: `spec/requests/queries/executions/show_spec.rb` の「他ユーザーのクエリ配下は404」を
  「他ユーザーのクエリ配下でも 200 で再表示できる（フルオープン）」に変更（Red）→ 実装（Green）。
  存在しない query_id の 404 ケース、当該クエリ配下に無い execution id の 404 ケースは残置。
  `create` の所有者スコープ 404 テスト（`executions_spec.rb` の「returns 404 for another user's query」）は維持を確認。
- **実テスト結果（修正後・全体）**: `508 examples, 0 failures` / `Line Coverage: 98.88% (975 / 986)`。
  `bin/rubocop`: `145 files inspected, no offenses detected`。
