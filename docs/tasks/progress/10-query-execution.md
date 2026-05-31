# 作業進捗ログ — トピック10: 非同期実行・結果保存

> タスク `docs/tasks/10-query-execution.md` の作業ログ（時系列）。司令塔・Coder・Tester のアクションを記録。最大トピック（30タスク・10グループ）。

- **ステータス**: 🔄進行中
- **担当**: Coder

## 司令塔メモ（着手時の判断・名称読み替え）

- **新規マイグレーション必要**: `query_executions` テーブル → マイグレーション承認ゲート。
- **名称読み替え（重要・タスク doc は前提名が実装と異なる）**:
  - `Connection` → **`Bigquery::Connection`**（`#bigquery` / `#over_limit?` / `#job_options`（maximum_bytes_billed 付与, トピック08））。
  - `DryRun` PORO は `app/models/dry_run.rb`（トピック08。doc の `app/models/bigquery/dry_run.rb` は誤り）。
  - `QuerySqlTransformer.transform` → **`Query#bound_sql`**（トピック09。`{{name}}`→`@name`）。
  - `Bigquery::ParameterBinder` → **`QueryParameter#to_bigquery_param`（Rubyネイティブ値）＋ `Query#permit_parameter_values`（ホワイトリスト）＋ `Query#missing_parameter_values`（全パラメータ必須）**（トピック09）。BigQuery 実行は `bigquery.query(sql, params:, types:)` 方式。
  - `Query` の接続は `bigquery_connection`（NOT NULL）。
- **未決事項の決定（司令塔）**:
  - 圧縮形式: **JSON + `Zlib::Deflate`（gzip）**（00-overview B で確定）。
  - 全件CSV: **実行成功時にジョブが `storage/csv/<query_execution_id>.csv.gz` へ書き出し、X-Sendfile（Thruster）で即時配信**（再フェッチなし、最新1件のみ保持・古いものは削除）（00-overview C で確定）。
  - Turbo Streams 購読先: **`turbo_stream_from @query`**（同一クエリの複数ウィンドウで結果を受け取れる）。
  - ポーリング: ジョブ内で **`job.wait_until_done!`**（ワーカースレッドはブロックしてよい。スレッド数を増やす）。
  - 同時実行20上限: `QueryExecution.where(status: [:running, :pending]).count >= 20` で `pending` 待機。SolidQueue 側 `concurrency`/threads も増やす。
  - `result_blob` は SQLite `binary`（圧縮後10MB上限を二重上限で担保）。

## 時系列ログ

### 2026-05-31

- **司令塔**: トピック09完了を受け、依存（04・07・08・09）充足済みの最大トピック10に着手。新規 Coder をアサイン。`query_executions` テーブルのマイグレーションが必要 → 承認ゲート。確認用ドキュメント作成を指示。
- **Coder→司令塔**: `query_executions` マイグレーション＋確認ドキュメント作成。論点4点（status default pending / (query_id,created_at) index不採用 / result_truncated default false nullable / result_row_count 意味は後続）を提起。司令塔: いずれも妥当と承認。
- **司令塔→人間**: `query_executions` マイグレーション承認を依頼。
- **人間→司令塔**: ✅承認。`db:migrate` 実行を許可。
- **司令塔→Coder**: マイグレーション実行＋トピック10 本体（モデル/圧縮blob/ジョブ/コントローラ/Turbo Streams/CSV/UI）を TDD で実装するよう指示。

### 2026-05-31（Coder 本実装・全グループ完了）

- **マイグレーション**: 承認済み `20260531130000_create_query_executions` を `db:migrate`＋`db:test:prepare` で適用。`db/schema.rb` を `version: 20260531130000` に更新。
- **G1 QueryExecution モデル（TDD red→green）**: `app/models/query_execution.rb`（`belongs_to :query` / `enum :status`（Rails 8 構文, default "pending"）/ `status` presence）。`Query` に `has_many :query_executions, dependent: :destroy` ＋ `#latest_succeeded_execution`（succeeded を created_at 降順で最新1件）。`spec/models/query_execution_spec.rb`・`spec/factories/query_executions.rb`・`query_spec.rb` に関連/enum/バリデーション/latest を追加。commit。
- **G2 圧縮blob＋QueryResult（TDD）**: `QueryExecution#store_result`（`Zlib::Deflate.deflate(JSON.generate({schema:,rows:}))`）／`#result`（Inflate→JSON.parse で `{schema:,rows:}`、未保存は nil）。PORO `app/models/query_result.rb`：二重上限（10,000行 or 圧縮後10MB）で先頭N行に切り詰め `truncated:`。`spec/models/query_result_spec.rb`（行数境界・圧縮サイズ＝ランダム非圧縮データで 8,000行≒17MB を切り詰め）。
- **G3 実行ジョブ（TDD）**: `app/jobs/query_execution_job.rb`（`queue_as :query_execution`）。running!→`bound_sql`＋`bigquery_params`（permit＋`to_bigquery_param`、date_range Hash は展開マージ）→`query_job(params:, **job_options)`→`wait_until_done!`→全件CSVを `storage/csv/<id>.csv.gz` へ gzip 書き出し→`QueryResult` 切り詰め→`store_result`/`result_row_count`/`result_truncated`→succeeded!→`broadcast_result`。失敗時 failed!＋error_message。`broadcast_result` はクラスメソッド（spec でスタブ）。`spec/jobs/query_execution_job_spec.rb`（succeeded/CSV/broadcast/job options/失敗2種/truncate）。`config/queue.yml` に `query_execution` ワーカー（threads 20）。`Gemfile` に `csv`（Ruby 3.4 対応）。
- **G4 コントローラ/ルート（TDD）**: `Queries::ExecutionsController`（require_login＋所有者スコープ `current_user.queries`、`missing_parameter_values` 非空なら 422＋error partial、同時実行 `where(status:[:running,:pending]).count>=20` で pending、`perform_later(execution, permit_parameter_values)`）。ルート `resources :executions, only:[:create], module:"queries"` ＋ `get latest/csv`。`spec/requests/queries/executions_spec.rb`（正常/whitelist/未入力422/上限pending/未認証redirect/他人404）。
- **G5 Turbo Streams**: Turbo 標準 `turbo_stream_from @query`＋`Turbo::StreamsChannel.broadcast_replace_to(query, target:"query_result", ...)`（専用 channel は作らず）。partial `_running`/`_result`/`_error`/`_state`。`spec/jobs/query_execution_broadcast_spec.rb` で broadcast 実体（target/partial）を検証。
- **G6 CSV（X-Sendfile, TDD）**: `Queries::Executions::CsvExportsController`（最新 succeeded の `storage/csv/<id>.csv.gz` を `send_file x_sendfile:true`、なし/ファイル無は404、truncated でも全件）。test/production に `x_sendfile_header = "X-Sendfile"`。`spec/requests/queries/executions/csv_exports_spec.rb`。`.gitignore` で `storage/csv/` 保持・中身無視、`.keep` 追加。
- **G7 UI**: `queries/show.html.erb` に単一フォーム（POST 実行＋GET プレビューを `formaction/formmethod` で両立し topic-09 の「パラメータを適用」を非破壊維持）・`turbo_stream_from @query`・`_state` 結果エリア・truncated バナー（全件CSV誘導）。`QueriesController#show` で `@latest_execution` を読み込み。
- **G8 worker**: `config/queue.yml`（`config/solid_queue.yml` は不在）に threads 20 ワーカー。`Procfile` の `worker: bundle exec bin/jobs` 既存確認。
- **G9 System Spec**: `spec/system/query_execution_spec.rb`（rack_test＋`queue_adapter=:inline`＋BigQuery スタブ、成功/失敗/truncated）／`spec/system/csv_export_spec.rb`（CSVリンク＋X-Sendfile配信）。
- **G10 品質ゲート**: `bundle exec rspec` **322 例 / 0 失敗**・SimpleCov **98.68%**（≥85%）。`bin/rubocop` 0 offense。`bin/brakeman --no-pager` **警告0**（High ゼロ。CSV の SendFile Weak＝検証済み false positive を `config/brakeman.ignore` に記録）。`bin/importmap audit` 脆弱性0。topic-09 system spec 含む既存テストの回帰なし。
- **追加マイグレーション**: なし（query_executions の範囲内）。SolidQueue/SolidCable の新規テーブル追加も不要。
- **コミット**: G1/G2、G3、G4-G7、G9/G10 の論理単位で 4 コミット（+ マイグレーション準備の既存コミット）。
- **Coder→司令塔**: トピック10 全グループ実装完了。Tester へ引き継ぎ。
