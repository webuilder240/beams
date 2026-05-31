# トピック10: 非同期実行・結果保存

> 実行ボタンで`QueryExecution`をSolidQueueに投入し、BigQuery完了後にTurbo Streamsで結果をプッシュ。圧縮blob1レコードに保存し、CSVダウンロードも提供する。計画書 §4.6 / §6.1 / §6.2 / §6.3 に対応。

- **ステータス**: 完了
- **依存**: [[04-bigquery-connection]]（`Connection`モデル・BigQueryクライアントラッパー・`maximum_bytes_billed`）／[[07-query-editor]]（`Query`モデル）／[[08-cost-protection]]（`Connection#over_limit?`・`DryRun` PORO）／[[09-parameterized-query]]（`ParameterBinder`・`SqlTransformer`）
- **関連計画書**: §4.6, §6.1, §6.2, §6.3

## ゴール（完了の定義）
- 実行ボタン押下 → `QueryExecution(status: running)` 作成 → SolidQueueに投入 → 即「実行中」画面が返る
- ジョブ内でBigQueryにジョブ投入・完了ポーリング → 結果保存 → Turbo Streams（SolidCable）で画面に差し込まれる
- 結果は最新成功1件のみ（上書き、履歴なし）
- 二重上限（10,000行 かつ 圧縮後10MB）超過時は先頭N行のみ保存しCSVダウンロードに誘導
- 結果は圧縮blob（列スキーマ＋行データを1レコード）で保存される
- 同時実行最大20件。超過はキュー待機し、UIに「実行待ち」が表示される
- CSVダウンロードがX-Sendfile（Thruster）経由で動作する
- RSpecでジョブ・モデル・コントローラ・Turbo Stream・Systemの各レイヤーをカバー

## 前提・参照
- [[04-bigquery-connection]] で `Connection` モデル・`maximum_bytes_billed`・BigQueryクライアントラッパーが実装済みであること
- [[07-query-editor]] で `Query` モデルが実装済みであること
- [[08-cost-protection]] で `Connection#over_limit?`・`DryRun` PORO（`app/models/bigquery/dry_run.rb`）が実装済みであること
- [[09-parameterized-query]] で `QuerySqlTransformer`・`Bigquery::ParameterBinder` が実装済みであること
- SolidQueue: `ApplicationJob` を継承し、`queue_as :query_execution` を指定
- SolidCable: `ActionCable.server.broadcast` でTurbo Streamsメッセージを配信
- Thruster（X-Sendfile）: `send_file` でCSVを配信。ファイルは `/storage/exports/` 以下に一時生成
- 圧縮形式: `JSON + Zlib::Deflate`（gzip）固定。追加gemは不要（Ruby標準の `Zlib` を使用）
- 計画書 §6.2: workerスレッドは多め（`config/solid_queue.yml` の `concurrency` を増やす）

## タスク

### グループ1: QueryExecutionモデル
- [x] `query_executions` テーブルを作成するマイグレーション (`db/migrate/YYYYMMDDHHMMSS_create_query_executions.rb`) を作成する — カラム: `query_id:references`, `status:string`, `error_message:text`, `result_blob:binary`, `result_row_count:integer`, `result_truncated:boolean`, `result_schema:text`（JSON）, `started_at:datetime`, `finished_at:datetime`
  - 受け入れ条件: `bin/rails db:migrate` が通る。`status` にDBインデックスを追加する
- [x] `app/models/query_execution.rb` を作成する — `belongs_to :query`, `enum status: { pending: "pending", running: "running", succeeded: "succeeded", failed: "failed" }`, バリデーション（`status` 必須）
  - 受け入れ条件: 不正な `status` でバリデーションエラー。`pending`/`running`/`succeeded`/`failed` の遷移が設計通りであることをモデルテストで確認
- [x] `Query` に「最新成功`QueryExecution`」を返す `latest_succeeded_execution` スコープを追加する (`app/models/query.rb`)
  - 受け入れ条件: 複数の `succeeded` が存在する場合に最新1件が返るテストが通る
- [x] **[TDD]** `spec/models/query_execution_spec.rb` を先に作成する（red を確認してから実装に進む）
  - 受け入れ条件: `enum`・バリデーション・関連のテストをカバーし、テスト green まで完了にしない

### グループ2: 圧縮blob保存（モデルメソッド）
- [x] **[TDD: 先に失敗するRSpec]** `spec/models/query_execution_spec.rb` にシリアライズのテストを追加する — `#store_result(schema, rows)` が `result_blob` に JSON + gzip バイナリを書き込み、`#result` でデシリアライズして `{ schema: Array, rows: Array }` を返すことを検証するテストを先に書き、red を確認してから実装に進む
  - 受け入れ条件: 先に失敗する RSpec が存在する状態を確認してから実装を開始すること
- [x] `app/models/query_execution.rb` に `#store_result(schema, rows)` と `#result` を追加する — `Zlib::Deflate.deflate(JSON.generate({schema:, rows:}))` で `result_blob` に保存し、`#result` は `Zlib::Inflate.inflate` → `JSON.parse` で `{ schema: Array, rows: Array }` を返す
  - 受け入れ条件: JSON + gzip でシリアライズ→デシリアライズのラウンドトリップテストが green になること
- [x] **[TDD]** 二重上限チェックロジックを `app/models/query_result.rb`（PORO `QueryResult`）に実装する — 10,000行超または圧縮後10MB超の場合は先頭N行に切り詰め、`truncated: true` を返す。先にテストを書いてから実装する
  - 受け入れ条件: 10,001行入力で10,000行に切り詰められ `truncated: true` が返るテストが green になること。圧縮後サイズ境界テストも同様。`spec/models/query_result_spec.rb` に配置し、テスト green まで完了にしない

### グループ3: BigQuery実行ジョブ
- [x] `app/jobs/query_execution_job.rb` を作成する — SolidQueueジョブ。処理フロー:
  1. `QueryExecution#running!` に更新
  2. `QuerySqlTransformer.transform` でSQL変換
  3. `Bigquery::ParameterBinder` でパラメータ生成
  4. BigQueryクライアントでジョブ投入（`maximum_bytes_billed` 付与）
  5. 完了ポーリング（`job.wait_until_done!` またはループ）
  6. 全件CSVを `storage/csv/<query_execution_id>.csv.gz` に書き出す（gzip圧縮）。既存ファイルは上書きして1件のみ保持
  7. `QueryResult` PORO で先頭N行に切り詰め（二重上限チェック）、`#store_result(schema, rows)` で圧縮blob作成
  8. `QueryExecution` を `succeeded` に更新・blob保存
  9. `ActionCable.server.broadcast` でTurbo Streamsに配信
  10. エラー時は `failed!` に更新・`error_message` 保存・エラーもブロードキャスト
  - 受け入れ条件: BigQuery APIをスタブ化し、succeeded遷移・broadcast呼び出しをRSpecで確認
- [x] `config/queue.yml`（SolidQueue設定）に `query_execution` キューと `concurrency: 20` を追加する
  - 受け入れ条件: `bin/jobs` 起動時に `query_execution` キューが読まれる
- [x] 同時実行20件上限のカウントロジックを実装する — `QueryExecution.where(status: [:running, :pending]).count >= 20` の場合は `pending` のまま待機し、UIに「実行待ち」を返す
  - 受け入れ条件: 21件目の実行リクエストで `status: pending` の `QueryExecution` が作られジョブが待機するテストが通る
- [x] **[TDD]** `spec/jobs/query_execution_job_spec.rb` を先に作成する — 正常系（succeeded）・BigQueryエラー系（failed）・上限ガード発動系のテストを先に書いてから実装に進む
  - 受け入れ条件: 全ケースが green になること。BigQuery APIはスタブ化。テスト green まで完了にしない

### グループ4: コントローラ・ルーティング
- [x] `app/controllers/queries/executions_controller.rb` を作成する — `POST /queries/:query_id/executions` で `QueryExecution` を作成し、SolidQueueにエンキューし、即座に実行中画面（Turbo Stream または redirect）を返す
  - 受け入れ条件: 正常時は `status: 201` または redirect。同時実行上限時は `pending` ステータスで作成される
- [x] `config/routes.rb` に `resources :queries do; resources :executions, only: [:create], module: 'queries'; end` を追加する
  - 受け入れ条件: `bin/rails routes` で `POST /queries/:query_id/executions` が確認できる
- [x] **[TDD]** `spec/requests/queries/executions_spec.rb` を先に作成する（red 確認後に実装）
  - 受け入れ条件: 正常系・上限超過系・未認証（401）のケースが green になること。テスト green まで完了にしない

### グループ5: Turbo Streams（SolidCable）リアルタイム反映
- [x] ActionCableチャンネル — **Turbo Rails 標準の `Turbo::StreamsChannel`（`turbo_stream_from @query`）を利用**し、専用 `query_execution_channel.rb` は作らない（実装メモ参照）
  - 受け入れ条件: Turbo の `turbo_stream_from @query` でサブスクライブ・差し込みが動作する
- [x] `app/views/query_executions/_result.html.erb` パーシャルを作成する — 結果テーブルを描画する
  - 受け入れ条件: カラム名ヘッダー・行データが正しく表示される
- [x] `app/views/query_executions/_error.html.erb` パーシャルを作成する — エラーメッセージを表示する
  - 受け入れ条件: `error_message` が表示される
- [x] ジョブ内の `ActionCable.server.broadcast` で `Turbo::StreamsChannel` に差し込む処理を実装する — `turbo_stream.replace "query_result", partial: "query_executions/result"` の形式
  - 受け入れ条件: ジョブのRSpecでブロードキャストが呼ばれることをスタブで確認
- [x] クエリ詳細画面（`app/views/queries/show.html.erb`）に `turbo_stream_from @latest_execution` と結果エリア（`id="query_result"`）を追加する
  - 受け入れ条件: 実行中は「実行中...」スピナーが表示され、完了後に結果が差し込まれる

### グループ6: CSVダウンロード（X-Sendfile）
- [x] `app/controllers/queries/executions/csv_exports_controller.rb` を作成する — `GET /queries/:query_id/executions/latest/csv` で最新成功 `QueryExecution` の全件CSVをX-Sendfileで即時配信する
  - フロー: `storage/csv/<query_execution_id>.csv.gz`（ジョブが実行成功時に書き出し済み）を `send_file` with `x_sendfile: true` → Thrusterが配信。BigQuery再フェッチは行わない
  - 受け入れ条件: レスポンスに `X-Sendfile` ヘッダーが含まれ、`Content-Type: text/csv` になるリクエストスペックが通る。先頭N行のみ表示のケース（`result_truncated: true`）でも全件CSVがダウンロードできる
- [x] `config/routes.rb` に csv エクスポートのルートを追加する
  - 受け入れ条件: `bin/rails routes` でルートが確認できる
- [x] **[TDD]** `spec/requests/queries/executions/csv_exports_spec.rb` を先に作成する（red 確認後に実装）
  - 受け入れ条件: 正常系・最新成功Executionなし（404）・`result_truncated: true` でも全件CSVが返るケースが green になること。テスト green まで完了にしない

### グループ7: 結果表示UI
- [x] クエリ詳細ビュー（`app/views/queries/show.html.erb`）に実行ボタン・実行状態表示・結果テーブルエリアを実装する
  - 受け入れ条件: `pending` では「実行待ち」、`running` では「実行中...」、`succeeded` では結果テーブル、`failed` ではエラーメッセージが表示される
- [x] 結果テーブルが10,000行truncatedの場合、「全件はCSVダウンロード」バナーを表示する
  - 受け入れ条件: `result_truncated: true` の `QueryExecution` で表示されるビューテストが通る

### グループ8: SolidQueue worker設定
- [x] **`config/queue.yml`**（本リポジトリの SolidQueue 設定。`config/solid_queue.yml` は存在しない）の `query_execution` キューworkerの `threads` を増やす（threads: 20）
  - 受け入れ条件: `bin/jobs` 起動時に `query_execution` キュー（threads 20）が読まれる
- [x] `Procfile` の `worker` エントリが `bundle exec bin/jobs` を指定していることを確認する
  - 受け入れ条件: `Procfile` に `worker: bundle exec bin/jobs` が存在する

### グループ9: System Spec
- [x] `spec/system/query_execution_spec.rb` を作成する（`rack_test` ドライバー、非同期部分はジョブをインラインで実行）
  - 受け入れ条件: 実行ボタン押下→`QueryExecution`作成→ジョブ実行→結果表示の一連フローが通る
- [x] `spec/system/csv_export_spec.rb` を作成する
  - 受け入れ条件: CSVダウンロードリンクをクリックするとダウンロードが開始される

### グループ10: テスト整合
- [x] `bundle exec rspec` でSimpleCov 85% 以上（プロジェクト規約）をクリアすることを確認する
  - 受け入れ条件: exit code 0（または 1）。exit code 2（カバレッジ不足）にならない。各グループのテストが全て green であること

## 動作確認
> 自動テスト（RSpec: request/job/system rack_test + インラインジョブ）でカバー済みの項目に [x]。
> 実 BigQuery・実 worker・実ブラウザでの手動確認は Tester／手動検証に申し送り（[手動] と明記）。
- [x] クエリエディタで `SELECT 1` を実行し、「実行中」画面が即座に表示されることを確認する（request/system spec でカバー。[手動] 実ブラウザの即時 Turbo 応答は要確認）
- [ ] [手動] SolidQueueのworkerが起動した状態でジョブが処理され、Turbo Streamsで結果が差し込まれることを確認する（job/broadcast spec はスタブ確認済み。実 worker＋WebSocket は手動）
- [x] 21件目の実行が「実行待ち」になり、先行ジョブ完了後にキューが消化されることを確認する（request spec で 20 件 running 時に 21 件目が pending になることを確認。[手動] 実消化は worker 手動）
- [x] 10,001行を返すクエリを実行し、10,000行のみ保存されて「全件はCSVダウンロード」バナーが表示されることを確認する（job spec＋system spec でカバー）
- [x] CSVダウンロードで全件が取得できることを確認する（csv_exports request/system spec でカバー。[手動] 実 Thruster 配信は手動）
- [x] `bin/brakeman --no-pager` で `High` Confidence警告がゼロであることを確認する（High はゼロ。Weak の SendFile false positive 1 件を `config/brakeman.ignore` に記録し、警告0）

## 未決事項・質問
- ✅ 決定（2026-05-31）圧縮形式: **JSON + `Zlib::Deflate`（gzip）** で確定。MessagePackは使わない（追加gem不要）。
- ✅ 決定（2026-05-31）CSVダウンロード全件配信: **実行成功時にジョブが全件CSVを `storage/csv/<query_execution_id>.csv.gz` へ書き出し、ダウンロードはX-Sendfileで即時配信**（BigQuery再フェッチなし）。表示用の先頭N行blobとは別管理。全件CSVは最新1件のみ保持（上書き）し肥大化を抑える。古い実行のCSVは削除する。
- ✅ 決定（2026-05-31）`result_blob` のカラム型: **`binary`（SQLite BLOB）**。圧縮後 10MB 上限は `QueryResult` の二重上限で担保するため Active Record 側のサイズ制限は付けない。
- ✅ 決定（2026-05-31）Turbo Streams のブロードキャスト先: **`turbo_stream_from @query`**（同一クエリの複数ウィンドウで結果を受け取れる）。ジョブは `Turbo::StreamsChannel.broadcast_replace_to(query, target: "query_result", ...)` で差し込む。
- ✅ 決定（2026-05-31）ポーリング方式: **`job.wait_until_done!`（ブロッキング）**。`query_execution` 専用ワーカーのスレッド数を増やして（`config/queue.yml`, threads 20）並行ブロックを許容する。独自ループは採用しない。

## 実装メモ（doc の前提名・記述からの読み替え／差分）
- **名称読み替え（司令塔確定）**: `Connection`→`Bigquery::Connection` / `DryRun` は `app/models/dry_run.rb` / `QuerySqlTransformer.transform`→`Query#bound_sql` / `Bigquery::ParameterBinder`→`QueryParameter#to_bigquery_param` ＋ `Query#permit_parameter_values` ＋ `Query#missing_parameter_values`。BigQuery 実行は `connection.bigquery.query_job(sql, params:, **job_options)` ＋ `wait_until_done!`。
- **ActionCable チャンネル（G5）**: 専用 `query_execution_channel.rb` は作らず、Turbo Rails 標準の `Turbo::StreamsChannel`（`turbo_stream_from @query`）を利用。これで「サブスクライブ／結果差し込み」の受け入れ条件を満たす（Turbo が購読・配信を担う）。
- **worker 設定（G8）**: `config/solid_queue.yml` は本リポジトリに存在せず、SolidQueue 設定は `config/queue.yml`。同ファイルに `queues: "query_execution" / threads: 20` のワーカーを追加した。
- **CSV の X-Sendfile**: `send_file ... x_sendfile: true` ＋ test/production の `config.action_dispatch.x_sendfile_header = "X-Sendfile"`。パスは `execution.id.to_i` のみから組み立て、ダウンロード名は `#download_filename` でサニタイズ。Brakeman SendFile（Weak）の検証済み false positive は `config/brakeman.ignore` に記録。
- **csv gem**: Ruby 3.4 で default gem から外れたため `Gemfile` に `gem "csv"` を追加。
- **全パラメータ必須**: `missing_parameter_values` が空でなければ実行せず 422＋エラー partial を返す。
- **品質ゲート**: `bundle exec rspec` 322 例 0 失敗・SimpleCov 98.68%、`bin/rubocop` 0、`bin/brakeman` 警告0、`bin/importmap audit` 脆弱性0。
