# トピック06: スキーマブラウザ・スキーマキャッシュ

> BigQueryメタデータをSQLiteにキャッシュし、左ペインのツリーUIでデータセット→テーブル→カラムを探索できるようにする。計画書 §4.3（後半）/ §6.4 に対応。

- **ステータス**: 未着手
- **依存**: [[04-bigquery-connection]]（BigQueryクライアントラッパー・Connectionモデルが必要）
- **関連計画書**: §4.3, §6.4

## ゴール（完了の定義）

- BigQueryの datasets.list / tables.list / `INFORMATION_SCHEMA.COLUMNS` でメタデータを取得できる
- 取得したメタデータがSQLiteモデル（SchemaDataset / SchemaTable / SchemaColumn）に保存される
- キャッシュ戦略（手動更新ボタン・初回アクセス時取得・TTL 24時間）が動作する
- 左ペインのツリーUI（データセット → テーブル → カラム）がStimulusで折りたたみ展開できる
- ツリー上のカラム名・テーブル名をクリックするとクエリエディタに名前が挿入される（[[07-query-editor]] との連携）
- スキーマブラウザ単体のRSpecモデルスペック・リクエストスペックのカバレッジが通る

## 前提・参照

- [[04-bigquery-connection]] で用意される `Connection` モデルおよびBigQueryクライアントラッパーを使用する
- [[07-query-editor]] のStimulusコントローラに名前挿入イベントを送る（カスタムイベント or Stimulusアウトレット）
- Hotwire（Turbo / Stimulus）、importmap（Node不使用）
- オートコンプリートは非スコープ（§5）
- `app/javascript/controllers/` 以下にStimulusコントローラを配置

## タスク

### 1. スキーマキャッシュ用モデル

- [ ] `SchemaDataset` モデル・マイグレーション作成（`app/models/schema_dataset.rb`, `db/migrate/YYYYMMDDHHMMSS_create_schema_datasets.rb`）— `connection_id`, `dataset_id`, `fetched_at`（datetime）, `name`（string）を持つ
  - 受け入れ条件: `bin/rails db:migrate` が通り、`SchemaDataset.create!` でレコードが保存できる
- [ ] `SchemaTable` モデル・マイグレーション作成（`app/models/schema_table.rb`, `db/migrate/YYYYMMDDHHMMSS_create_schema_tables.rb`）— `schema_dataset_id`（FK）, `table_id`, `table_type`（string）, `fetched_at`（datetime）を持つ
  - 受け入れ条件: `SchemaDataset` との `belongs_to` / `has_many` アソシエーションがRSpecで検証できる
- [ ] `SchemaColumn` モデル・マイグレーション作成（`app/models/schema_column.rb`, `db/migrate/YYYYMMDDHHMMSS_create_schema_columns.rb`）— `schema_table_id`（FK）, `column_name`, `data_type`, `is_nullable`（boolean）, `ordinal_position`（integer）を持つ
  - 受け入れ条件: `SchemaTable` との `belongs_to` / `has_many` アソシエーションがRSpecで検証できる
- [ ] 各モデルのFactoryBot定義（`spec/factories/schema_datasets.rb`, `spec/factories/schema_tables.rb`, `spec/factories/schema_columns.rb`）
  - 受け入れ条件: `create(:schema_dataset)` 等でRSpecのfactory_bot経由にて作成できる
- [ ] モデルスペック3本（`spec/models/schema_dataset_spec.rb`, `spec/models/schema_table_spec.rb`, `spec/models/schema_column_spec.rb`）— バリデーション・アソシエーションを検証
  - 受け入れ条件: `bundle exec rspec spec/models/schema_*` が全グリーン

### 2. スキーマ取得ロジック

> **コーディング規約**: `app/services/` ディレクトリおよび `*Service` 命名は禁止。ロジックは `Connection` のモデルメソッドか `app/models/` 配下のPOROに置く。テストは `spec/models/` に書く。**TDD**（先に失敗するRSpecを書いてから実装）。テストがグリーンになるまでタスク完了としない。

- [ ] **先にRSpecを書く**（`spec/models/connection_spec.rb` 内 or `spec/models/schema_sync_spec.rb`）— `Connection#sync_schema!` の呼び出し・TTL判定・upsert結果をBigQueryクライアントをstubして検証する失敗するスペックを先に作成する
  - 受け入れ条件: 実装前に `bundle exec rspec spec/models/schema_sync_spec.rb` が失敗（red）であること
- [ ] `Connection#sync_schema!` メソッド実装（`app/models/connection.rb`）— datasets.list / tables.list / `INFORMATION_SCHEMA.COLUMNS` を順に叩いてSchemaDataset/SchemaTable/SchemaColumnをupsertする。TTL判定（`fetched_at` が24時間以内なら取得をスキップ）も本メソッド内 or `SchemaDataset` のメソッドに実装する
  - 受け入れ条件: RSpecにてBigQueryクライアントをstubして呼び出しが正しく行われることを確認できる（`spec/models/connection_spec.rb` or `spec/models/schema_sync_spec.rb`）
  - 受け入れ条件: `fetched_at` が25時間前のレコードに対して再取得が走り、1時間前のレコードにはスキップすることをRSpecで確認できる
  - 受け入れ条件: 上記スペックが全グリーン（カバレッジ85%以上）になること
- [ ] 手動更新用のコントローラアクション追加（`app/controllers/schema_caches_controller.rb`）— `POST /schema_caches/refresh` でTTLを無視して `connection.sync_schema!(force: true)` を呼び出し、Turbo Stream or リダイレクトで応答
  - 受け入れ条件: リクエストスペック（`spec/requests/schema_caches_spec.rb`）でHTTP 302 or 200が返ることを確認

### 3. 初回アクセス時の自動取得

- [ ] クエリエディタページ（またはスキーマブラウザを含むレイアウト）のコントローラで、`SchemaDataset` が0件の場合に `connection.sync_schema!` を同期実行するbefore_action追加（`app/controllers/`、対象コントローラを [[07-query-editor]] の実装と合わせて決定）
  - 受け入れ条件: DBが空の状態でページを開くとスキーマが取得・保存されることをRSpecリクエストスペックで確認（BigQueryクライアントをstub）

### 4. スキーマブラウザUI

- [ ] スキーマブラウザ用パーシャル作成（`app/views/schema_browser/_schema_browser.html.erb`）— データセット→テーブル→カラムのネストしたリスト、`data-controller` 属性付き
  - 受け入れ条件: `bundle exec rspec spec/system/schema_browser_spec.rb`（rack_test）でHTMLにデータセット名が含まれることを確認
- [ ] Stimulusコントローラ作成（`app/javascript/controllers/schema_browser_controller.js`）— データセット・テーブルの折りたたみ/展開トグル、クリックで名前をクリップボードまたはエディタに挿入するカスタムイベント発火
  - 受け入れ条件: System Spec（`spec/system/schema_browser_spec.rb`、`js: true`）でテーブル名クリック後にエディタに名前が入ることを確認
- [ ] 手動更新ボタン（`app/views/schema_browser/_schema_browser.html.erb`内）— `POST /schema_caches/refresh` へTurboを使って送信し、ツリーを再描画
  - 受け入れ条件: System Spec（`js: true`）で更新ボタンクリック後にツリーが再描画されることを確認（BigQueryクライアントをstub）

### 5. ルーティング

- [ ] `config/routes.rb` に `resources :schema_caches, only: [] do collection { post :refresh } end` を追加
  - 受け入れ条件: `bin/rails routes | grep schema_cache` に `refresh` が表示される

### 6. RSpec・カバレッジ

- [ ] `bundle exec rspec spec/models/schema_* spec/models/connection_spec.rb spec/requests/schema_caches_spec.rb` が全グリーンかつSimpleCov 85%以上
  - 受け入れ条件: CI相当でカバレッジエラー（exit code 2）が出ない

## 動作確認

- [ ] `bin/rails db:migrate db:test:prepare` が通る
- [ ] rack_test System Spec（`spec/system/schema_browser_spec.rb`）でスキーマツリーHTMLが確認できる
- [ ] `js: true` のSystem SpecでCodeMirrorエディタへのテーブル名挿入が確認できる（BigQueryをstub）
- [ ] 手動更新ボタン押下でツリーが再描画されることを `js: true` System Specで確認

## 未決事項・質問

- `Connection#sync_schema!` の実行を同期（before_action）にするかバックグラウンドジョブ（SolidQueue）にするかは [[04-bigquery-connection]] および [[10-query-execution]] の設計を見てから決定。初期は同期を想定しているが、データセット数が多い場合の遅延に注意。`app/services/` やServiceクラスは使用しない。
- `INFORMATION_SCHEMA.COLUMNS` はデータセット単位でクエリが必要なため、取得コスト（BQクエリ課金）が発生する可能性がある。取得粒度（全データセット一括 vs. テーブル展開時のオンデマンド）は [[04-bigquery-connection]] の実装者と合わせて決定。
- Stimulusコントローラからクエリエディタへの名前挿入方法（カスタムイベント vs. Stimulusアウトレット）は [[07-query-editor]] の実装と合わせて確定させる。
