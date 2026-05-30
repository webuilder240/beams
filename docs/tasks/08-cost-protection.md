# トピック08: コスト保護（dry-run・上限ガード）★差別化の目玉

> 実行前に自動dry-runでスキャン量と推定コストを表示し、Connection単位の上限ガードで課金事故を防ぐ。計画書 §4.4 に対応。

- **ステータス**: 未着手
- **依存**: [[04-bigquery-connection]]（`Connection`モデル、`maximum_bytes_billed`カラム、BigQueryクライアントラッパー）／[[07-query-editor]]（`Query`モデル）
- **関連計画書**: §4.4, §1.4

## ゴール（完了の定義）
- クエリエディタの実行ボタン横に「推定 ◯ GB / 約 ¥◯」が自動表示される
- `Connection#maximum_bytes_billed` が全実行ジョブに付与される
- 上限超過時はdry-runで弾かれ、具体的エラーメッセージが表示される
- GB→円換算のレート単価が管理画面で設定可能
- dry-runは課金ゼロで実行される（`dry_run: true` フラグを使用）
- RSpecでdry-runロジック・換算ロジック・上限判定をカバー

## 前提・参照
- [[04-bigquery-connection]] で `Connection` モデルに `maximum_bytes_billed: bigint` カラムおよびBigQueryクライアントラッパーが実装済みであること
- [[07-query-editor]] で `Query` モデルが実装済みであること
- BigQuery dry-run: `google-cloud-bigquery` gem の `Dataset#query_job` に `dry_run: true` を渡すと課金ゼロでバイト数のみ返る
- BigQueryオンデマンド料金（2024年時点）: $6.25/TB（= 約¥950/TB）。単価は設定で上書き可能にする
- 計画書 §4.10: 初回セットアップウィザードでのコスト上限設定（任意ステップ）とも連携

## タスク

### グループ1: dry-run・コスト換算 PORO
- [ ] **先に失敗するRSpecを書く**: `spec/models/dry_run_spec.rb` を作成する
  - 受け入れ条件: `DryRun.new(connection, sql).call` が `{ bytes_processed: Integer }` を返すテストが red になること。BigQuery APIは `instance_double` でスタブ化
- [ ] `app/models/dry_run.rb` を作成する — BigQueryクライアントに `dry_run: true` でジョブを投入し、スキャンバイト数（`statistics.total_bytes_processed`）を返す PORO
  - 受け入れ条件: 上記 RSpec が green になること（正常系・接続エラー系をカバー）
- [ ] **先に失敗するRSpecを書く**: `spec/models/cost_estimate_spec.rb` を作成する
  - 受け入れ条件: `CostEstimate.new(bytes: 5_368_709_120, yen_per_tb: 950).estimate` が `{ gb: 5.0, yen: 4.75 }` を返すテストが red になること（バイト0・境界値・通常値のケースを含む）
- [ ] `app/models/cost_estimate.rb` を作成する — バイト数→GB換算、GB×単価→円換算のロジックを持つ純粋 PORO
  - 受け入れ条件: 上記 RSpec が green になること

### グループ2: 単価設定（ApplicationSetting）
- [ ] `ApplicationSetting` モデル（またはシングルトンレコード）に `bigquery_yen_per_tb: decimal` カラムを追加するマイグレーション (`db/migrate/YYYYMMDDHHMMSS_add_bigquery_yen_per_tb_to_application_settings.rb`) を作成する
  - 受け入れ条件: `bin/rails db:migrate` が通り、デフォルト値 950.0 が設定される
- [ ] `app/models/application_setting.rb` に `yen_per_tb` のバリデーション（数値・0以上）を追加する
  - 受け入れ条件: 負の値でバリデーションエラーになるモデルテストが通る
- [ ] 管理画面（admin）にコスト単価設定フォームを追加する (`app/views/admin/settings/`, `app/controllers/admin/settings_controller.rb`)
  - 受け入れ条件: adminユーザーが単価を更新できる。memberはアクセス不可（403）

### グループ3: dry-runコントローラ・エンドポイント
- [ ] `app/controllers/queries/dry_runs_controller.rb` を作成する — `POST /queries/:id/dry_run` を受け付け、`DryRun` と `CostEstimate` を呼び出してJSON（`{ gb, yen, over_limit, error }`）を返す
  - 受け入れ条件: `maximum_bytes_billed` 未設定時は `over_limit: false`、超過時は `over_limit: true` と `error_message` を返す
- [ ] `config/routes.rb` に `resources :queries do; resource :dry_run, only: [:create], module: 'queries'; end` を追加する
  - 受け入れ条件: `bin/rails routes` で `POST /queries/:query_id/dry_run` が確認できる
- [ ] `spec/requests/queries/dry_runs_spec.rb` を作成する
  - 受け入れ条件: 正常系（推定値返却）・上限超過系・BigQueryエラー系のリクエストスペックが通る

### グループ4: 上限ガードロジック
- [ ] **先に失敗するRSpecを書く**: `spec/models/connection_spec.rb`（既存があれば追記）に `Connection#over_limit?(bytes_processed)` のテストを追加する
  - 受け入れ条件: 未設定・上限内・上限超過の3ケースが red になること
- [ ] `Connection#over_limit?(bytes_processed)` モデルメソッドを実装する — `bytes_processed` と `maximum_bytes_billed` を比較し、超過なら `true`、`nil` なら常に `false`
  - 受け入れ条件: 上記 RSpec が green になること
- [ ] `LimitExceededError` を `app/models/` 配下（例: `app/models/limit_exceeded_error.rb`）に定義する
  - 受け入れ条件: コントローラが `rescue LimitExceededError` できること

### グループ5: フロントエンド（Stimulus + Turbo）
- [ ] `app/javascript/controllers/dry_run_controller.js` を作成する — クエリエディタのSQLが変化したときにdebounce（500ms）で `POST /queries/:id/dry_run` を叩き、結果を `data-dry-run-target="result"` に表示するStimulusコントローラ
  - 受け入れ条件: SQL変更から500ms後にfetchが走り、`推定 X.X GB / 約 ¥Y` テキストが更新される（System Specで確認）
- [ ] クエリエディタビュー (`app/views/queries/show.html.erb` または該当パーシャル) に `data-controller="dry-run"` と結果表示エリア・上限超過警告エリアを追加する
  - 受け入れ条件: 上限超過時に警告バナーが表示され、実行ボタンが非活性になる
- [ ] `spec/system/dry_run_spec.rb` を作成する（`rack_test` ドライバー、JSなし範囲でカバーできる部分のみ）
  - 受け入れ条件: dry-runエンドポイントへのフォーム送信→結果表示の流れが確認できる

### グループ6: テスト整合
- [ ] SimpleCov 85% ラインを下回らないことを `bundle exec rspec` で確認する
  - 受け入れ条件: 全スペックが green で exit code が 2 でないこと。各グループのタスクはテスト green を確認するまで完了にしない

## 動作確認
- [ ] adminで接続の `maximum_bytes_billed` を小さい値（例: 1 byte）に設定する
- [ ] クエリエディタで任意のSQLを入力し、500ms後に「推定 X GB / 約 ¥Y」が表示されることを確認する
- [ ] 上限超過の警告バナーが表示され、実行ボタンが非活性になることを確認する
- [ ] `maximum_bytes_billed` を十分大きい値に戻し、推定表示のみ（警告なし）になることを確認する
- [ ] `bin/brakeman --no-pager` がdry-runエンドポイントでSQL injection警告を出さないことを確認する

## 未決事項・質問
- dry-runはSQLを受け取るタイミング（保存前のエディタ内テキストvs保存済みQueryのSQL）をどちらにするか。保存前の場合は `Query` IDではなくSQLをリクエストボディで受け取る形になる。セキュリティ上はBigQuery側でdry-runするため問題ないが、ルート設計が変わる。→ 現状は「保存済みQuery IDベース」で設計したが要確認。
- `ApplicationSetting` が既存モデルとして別トピックで作成される場合、カラム追加のみに変更が必要。
- 換算レートは1つのグローバル設定か、Connection単位で持つか（§4.4は「設定可能」とのみ記載）。
