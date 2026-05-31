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
