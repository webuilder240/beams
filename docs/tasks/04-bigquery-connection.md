# トピック04: BigQuery接続・Connectionモデル

> SA JSON鍵とプロジェクトIDを Active Record Encryption で暗号化保存し、BigQueryクライアントを生成する `Connection` モデルを実装する。計画書 §4.2 に対応。

- **ステータス**: 完了
- **依存**: [[01-foundation-rename]]（Active Record Encryption の設定キー生成・有効化が完了していること）、[[03-auth-users]]（admin 認可の before_action が使えること）
- **関連計画書**: §4.2, §4.4（`maximum_bytes_billed` カラム）

## ゴール（完了の定義）

- `google-cloud-bigquery` gem が Gemfile に追加されバンドルされている
- `Connection` モデルが SA JSON 鍵（暗号化）・プロジェクト ID・コスト上限（`maximum_bytes_billed`）を保存できる
- SA JSON 鍵は Active Record Encryption で暗号化されて SQLite に保存される（平文が DB に書かれない）
- `Connection#bigquery` メソッドが `Google::Cloud::Bigquery` クライアントを返す
- admin のみが `Connection` の CRUD 画面にアクセスできる
- データモデルは複数 Connection を持てる構造（UI・初期運用は 1 接続）
- 各機能はテストを先に書き（Red → Green）、RSpec で主要パスがカバーされ、SimpleCov 85% 以上を維持する

## 前提・参照

- Active Record Encryption の設定（`config/application.rb` の `config.active_record.encryption.*`）は [[01-foundation-rename]] で完了済み
- `credentials.yml.enc` または環境変数で暗号化キーが注入されている前提
- `google-cloud-bigquery` Ruby gem: https://github.com/googleapis/google-cloud-ruby/tree/main/google-cloud-bigquery
- BigQuery `maximum_bytes_billed` の実際の適用（実行ジョブへの付与）は [[08-cost-protection]] で行う。本トピックはカラム追加と設定 UI のみ
- admin 認可ヘルパー（`require_admin`）は [[03-auth-users]] で実装済み

## タスク

### gem 導入

- [x] `google-cloud-bigquery` を Gemfile に追加（`Gemfile`）— `gem "google-cloud-bigquery"`。バージョンは追加時点の最新安定版を指定
  - 受け入れ条件: `bundle install` が成功し、`bundle exec ruby -e "require 'google/cloud/bigquery'; puts 'ok'"` が `ok` を出力する
- [x] `bundle install` 後に `Gemfile.lock` をコミット対象に含める
  - 受け入れ条件: `git diff Gemfile.lock` に `google-cloud-bigquery` の依存グラフが含まれている

### Connection モデル

- [x] `Connection` モデル・マイグレーション作成（`app/models/connection.rb`, `db/migrate/YYYYMMDDHHMMSS_create_connections.rb`）— `name:string`, `project_id:string`, `service_account_json:text`（暗号化対象）, `maximum_bytes_billed:bigint`（NULL 可 = 上限なし）, `created_at`, `updated_at`
  - 受け入れ条件: `rails db:migrate` が通り、`Connection.new` でインスタンスが作れる
- [x] `Connection` モデルに Active Record Encryption を設定（`app/models/connection.rb`）— `encrypts :service_account_json`
  - 受け入れ条件: `Connection.create!(...)` で保存後、SQLite ファイルを直接参照しても `service_account_json` カラムが平文でないこと（暗号化されたバイト列になっている）
- [x] `Connection` モデルにバリデーション追加（`app/models/connection.rb`）— `name` 必須、`project_id` 必須・フォーマット（英数字/ハイフン）、`service_account_json` 必須・JSON パース可能であること
  - 受け入れ条件: 不正な JSON 文字列を `service_account_json` に入れると `errors` に追加される
- [x] `maximum_bytes_billed` のバリデーション追加（`app/models/connection.rb`）— NULL または 0 より大きい整数
  - 受け入れ条件: `maximum_bytes_billed: -1` で保存しようとするとバリデーションエラーになる
- [x] FactoryBot ファクトリ作成（`spec/factories/connections.rb`）— `service_account_json` に Faker を使ったダミー JSON、`maximum_bytes_billed` は NULL または任意の数値
  - 受け入れ条件: `create(:connection)` が RSpec 内で使える
- [x] **[TDD: 先に失敗するテストを書く]** `spec/models/connection_spec.rb` にバリデーション・暗号化・`#bigquery` メソッドの正常/異常系テストを作成する（実装前に Red であることを確認する）
  - 受け入れ条件: テストが Red（失敗）の状態でコミットできる
- [x] `Connection` モデル単体テスト（`spec/models/connection_spec.rb`）を Green にする — バリデーション・暗号化の正常/異常系
  - 受け入れ条件: `bundle exec rspec spec/models/connection_spec.rb` がグリーン。テストが通るまで完了にしない

### BigQuery クライアント（`Connection#bigquery`）

- [x] **[TDD: 先に失敗するテストを書く]** `spec/models/connection_spec.rb` に `Connection#bigquery` が `Google::Cloud::Bigquery` インスタンスを返すテストを追加する（`google-cloud-bigquery` をモック/スタブ）
  - 受け入れ条件: テストが Red（失敗）の状態で確認できる
- [x] `Connection#bigquery` メソッド実装（`app/models/connection.rb`）— `service_account_json` と `project_id` を使って `Google::Cloud::Bigquery` クライアントを返す。SA JSON を一時ファイルまたはインメモリで渡す方法を選択する。補助ロジックが必要な場合は `app/models/` 配下の PORO に置く（`app/services/` および `*Service` 命名は禁止）
  - 受け入れ条件: `connection.bigquery` が `Google::Cloud::Bigquery` のインスタンスを返す（単体テストはモックで代替可）。`bundle exec rspec spec/models/connection_spec.rb` がグリーン。テストが通るまで完了にしない

### Connection 管理 UI（admin 専用）

- [x] **[TDD: 先に失敗するテストを書く]** `spec/requests/connections_spec.rb` に admin による CRUD・member によるアクセス拒否のテストを作成する（実装前に Red であることを確認する）
  - 受け入れ条件: テストが Red（失敗）の状態で確認できる
- [x] `ConnectionsController`（admin 専用）作成（`app/controllers/connections_controller.rb`）— `index`, `new`, `create`, `edit`, `update`, `destroy`。`before_action :require_admin`
  - 受け入れ条件: admin でログインした状態で接続一覧・作成・編集・削除が動作する。member でアクセスすると弾かれる
- [x] ルーティング追加（`config/routes.rb`）— `resources :connections`（または admin 名前空間）
  - 受け入れ条件: `rails routes` で connections の CRUD パスが確認できる
- [x] Connection フォームビュー作成（`app/views/connections/`）— `name`, `project_id`, `service_account_json`（`<textarea>`）, `maximum_bytes_billed` 入力欄。`service_account_json` は編集画面で既存値を表示しない（セキュリティ: 登録済みなら「変更する場合のみ入力」のプレースホルダ）
  - 受け入れ条件: フォームから接続を新規作成・編集できる。編集画面で SA JSON の平文が露出しない
- [x] Connection 一覧ビュー作成（`app/views/connections/index.html.erb`）— 接続名・プロジェクト ID・コスト上限を表示。SA JSON は表示しない
  - 受け入れ条件: 一覧画面に SA JSON カラムが出ない
- [x] `ConnectionsController` の RSpec テスト（`spec/requests/connections_spec.rb`）を Green にする — admin による CRUD、member によるアクセス拒否
  - 受け入れ条件: `bundle exec rspec spec/requests/connections_spec.rb` がグリーン。テストが通るまで完了にしない

### System Spec

- [x] Connection 管理のシステムスペック（`spec/system/connections_spec.rb`）— rack_test ドライバー。admin でログイン → 接続新規作成 → 一覧に表示 → 編集 → 削除の画面操作を検証
  - 受け入れ条件: `bundle exec rspec spec/system/connections_spec.rb` がグリーン

## 動作確認

- [x] `bundle exec rails db:migrate` → エラーなし
- [x] `rails console` で `Connection.create!(name: "本番", project_id: "my-project-123", service_account_json: '{"type":"service_account"}', maximum_bytes_billed: 10_000_000_000)` が保存できる
- [x] 保存後に `Connection.first.service_account_json` が元の JSON 文字列を返し、SQLite ファイルの生データは暗号化されている（`hexdump` 等で確認）
- [x] admin でブラウザから接続を作成・編集・削除できる
- [x] member でアクセスすると弾かれる
- [x] `bundle exec rspec spec/models/connection_spec.rb spec/requests/connections_spec.rb spec/system/connections_spec.rb` → 全グリーン
- [x] `bundle exec rspec` → SimpleCov 85% 以上

## 未決事項・質問

- ✅決定（2026-05-31, 実装者判断）: `service_account_json` は **インメモリのハッシュを `Google::Cloud::Bigquery.new(credentials:)` に渡す**方式を採用。`JSON.parse(service_account_json)` で得たハッシュをそのまま `credentials:` に渡せるため、**一時ファイルは不要**。`Connection#bigquery` 内でメモ化。
- ✅決定（2026-05-31, 実装者判断）: SA JSON 編集フォームの「変更しない場合は空欄」は、**コントローラの `connection_update_params` で空欄キーを `delete` し、`update` に渡さない**ことで既存値を保持。フォームは `value: ""` で常に空欄表示（平文を再表示しない）。
- `maximum_bytes_billed` の単位（バイト）を UI でどの単位で入力させるか（バイト/GB 変換 UI）は [[08-cost-protection]] 側で整備する。本トピックはバイト整数のカラムのみ。

## 実装メモ（2026-05-31 完了時）

- **命名**: 司令塔/ボス決定により**ネームスペース方式 `Bigquery::Connection`** を採用（タスク本文中の `Connection` / `connections` 表記は読み替え）。
  - モデル: `app/models/bigquery/connection.rb`、`app/models/bigquery.rb` の `table_name_prefix "bigquery_"` でテーブル `bigquery_connections` にマップ
  - マイグレーション: `db/migrate/20260531092141_create_bigquery_connections.rb`（`CreateBigqueryConnections`）
  - ファクトリ: `spec/factories/bigquery_connections.rb`（`:bigquery_connection`）
  - モデルspec: `spec/models/bigquery/connection_spec.rb`
  - コントローラ: `app/controllers/bigquery/connections_controller.rb`（`Bigquery::ConnectionsController`、`before_action :require_admin`）
  - ルーティング: `namespace :bigquery { resources :connections, except: [:show] }`（パス `/bigquery/connections`）
  - ビュー: `app/views/bigquery/connections/`（index / new / edit / _form / _errors）
  - リクエストspec: `spec/requests/bigquery/connections_spec.rb`、systemスペック: `spec/system/bigquery/connections_spec.rb`
- **テスト結果**: `bundle exec rspec` 全 81 例 green、SimpleCov 99.3%。`bin/rubocop` 0 offenses、`bin/brakeman --no-pager` 0 warnings。
