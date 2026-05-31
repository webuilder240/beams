# トピック06: スキーマブラウザ・スキーマキャッシュ（SolidCache 方式）

> BigQueryメタデータを **SolidCache（`Rails.cache`）にキャッシュ**し、左ペインのツリーUIでデータセット→テーブル→カラムを探索できるようにする。計画書 §4.3（後半）/ §6.4 に対応。
> **設計決定は [ADR 0001](../adr/0001-bigquery-schema-cache.md) を参照（3テーブル正規化はやめ、SolidCache に保存する方式に変更）。**

- **ステータス**: 進行中
- **依存**: [[04-bigquery-connection]]（BigQueryクライアントラッパー・`Bigquery::Connection`モデルが必要）
- **関連計画書**: §4.3, §6.4

## ゴール（完了の定義）

- BigQueryの datasets.list / tables.list / `INFORMATION_SCHEMA.COLUMNS` でメタデータを取得できる
- 取得したメタデータが **SolidCache（`Rails.cache`）にネスト構造のハッシュとして**保存される（キー `bigquery:schema:#{id}`）
- キャッシュ戦略（手動更新ボタン・初回アクセス時取得・TTL 24時間）が動作する
- 左ペインのツリーUI（データセット → テーブル → カラム）がStimulusで折りたたみ展開できる
- ツリー上のカラム名・テーブル名をクリックするとカスタムイベント `schema-browser:insert` が発火する（[[07-query-editor]] でエディタに配線）
- スキーマブラウザ単体のRSpecモデルスペック・リクエストスペック・rack_test system specのカバレッジが通る（SimpleCov 85%以上）

## 前提・参照

- [[04-bigquery-connection]] で用意される `Bigquery::Connection` モデルおよび `#bigquery` クライアントラッパーを使用する
- [[07-query-editor]] のStimulusコントローラに名前挿入イベント（`schema-browser:insert`、`detail` に挿入名）を送る
- Hotwire（Turbo / Stimulus）、importmap（Node不使用）
- オートコンプリートは非スコープ（§5）。**そのため関係クエリ不要 → SolidCache 採用（ADR 0001）**
- `app/javascript/controllers/` 以下にStimulusコントローラを配置
- ロジックは `*Service`/`app/services` 禁止 → `Bigquery::Connection` のモデルメソッドに置く

## タスク

### 1. スキーマ取得・キャッシュ（`Bigquery::Connection` のモデルメソッド）

> **コーディング規約**: `app/services/` および `*Service` 命名は禁止。ロジックは `Bigquery::Connection` のモデルメソッドに置く。テストは `spec/models/bigquery/`。**TDD**（先に失敗するRSpecを書いてから実装）。

- [ ] **先にRSpecを書く**（`spec/models/bigquery/connection_spec.rb`）— `#sync_schema!` がBigQueryクライアントをstubして正しくキャッシュへ書く / `#cached_schema` が初回sync・2回目はキャッシュ利用 / TTL（`travel 25.hours` で失効再取得、1時間後はキャッシュ利用）を検証する失敗するスペックを先に作成する
  - 受け入れ条件: 実装前にredであること
- [ ] `Bigquery::Connection#sync_schema!(force: false)` 実装 — datasets.list / tables.list / `INFORMATION_SCHEMA.COLUMNS` を順に叩いてネスト構造ハッシュを組み立て、`Rails.cache.write("bigquery:schema:#{id}", structure, expires_in: 24.hours)` で保存。`force: true` は無条件で再取得・上書き
  - 受け入れ条件: BigQueryクライアントをstubして呼び出しとキャッシュ書き込みが検証できる
- [ ] `Bigquery::Connection#cached_schema` 実装 — `Rails.cache.fetch(key, expires_in: 24.hours) { build... }` 相当で初回取得とTTLを両立
  - 受け入れ条件: `travel 25.hours` で失効し再取得、1時間後はキャッシュ利用をRSpecで確認
- [ ] 手動更新用コントローラ `SchemaCachesController#refresh`（`POST /schema_caches/refresh`）— TTLを無視して `connection.sync_schema!(force: true)` を呼び、リダイレクトで応答
  - 受け入れ条件: リクエストスペック（`spec/requests/schema_caches_spec.rb`）でHTTP 302 or 200

### 2. 初回アクセス時の自動取得

- [ ] スキーマブラウザを表示するコントローラ（`SchemaBrowsersController#show`）の before_action で `connection.cached_schema` を呼ぶ（キャッシュ未設定なら sync が走る）
  - 受け入れ条件: キャッシュ空の状態でページを開くとスキーマが取得・キャッシュされることをリクエストスペックで確認（BigQueryをstub）

### 3. スキーマブラウザUI

- [ ] スキーマブラウザ用パーシャル（`app/views/schema_browser/_schema_browser.html.erb`）— データセット→テーブル→カラムのネストしたリスト、`data-controller="schema-browser"` 付き、手動更新ボタン（`POST /schema_caches/refresh`）
  - 受け入れ条件: rack_test system spec（`spec/system/schema_browser_spec.rb`）でHTMLにデータセット名が含まれることを確認
- [ ] Stimulusコントローラ（`app/javascript/controllers/schema_browser_controller.js`）— データセット・テーブルの折りたたみ/展開トグル、名前クリックでカスタムイベント `schema-browser:insert`（`detail` に名前）を dispatch し、可能ならクリップボードへコピー
  - 受け入れ条件: 実際のエディタ配線は [[07-query-editor]] に委ねる。本トピックでは `js: true` テストは pending または最小確認とし、rack_test カバレッジを厚くする（環境で `js: true` が動かない場合は pending 理由を記載）

### 4. ルーティング

- [ ] `config/routes.rb` に `resources :schema_caches, only: [] do collection { post :refresh } end` と スキーマブラウザ表示用ルートを追加
  - 受け入れ条件: `bin/rails routes | grep schema` に `refresh` が表示される

### 5. テスト環境のキャッシュ設定

- [ ] `config/environments/test.rb` の `config.cache_store` を `:memory_store` に変更（デフォルトの `:null_store` だとキャッシュ検証ができないため）。**設定変更でありマイグレーションではない**

### 6. RSpec・カバレッジ

- [ ] `bundle exec rspec` 全体がグリーンかつSimpleCov 85%以上
  - 受け入れ条件: CI相当でカバレッジエラー（exit code 2）が出ない

## 動作確認

- [ ] `bundle exec rspec spec/models/bigquery/connection_spec.rb spec/requests/schema_caches_spec.rb spec/requests/schema_browsers_spec.rb spec/system/schema_browser_spec.rb` が全グリーン
- [ ] rack_test System SpecでスキーマツリーHTML（データセット名）が確認できる
- [ ] `js: true` のエディタ挿入テストは [[07-query-editor]] に委ねる（本トピックでは pending）

## 未決事項・質問

- `INFORMATION_SCHEMA.COLUMNS` はデータセット単位でクエリが必要なため、取得コスト（BQクエリ課金）が発生し得る。取得粒度（全データセット一括 vs オンデマンド）は初期は一括取得。将来調整余地あり（ADR 0001 Consequences）。
- Stimulusコントローラからクエリエディタへの名前挿入は **カスタムイベント `schema-browser:insert`** で疎結合化。実リスナは [[07-query-editor]] で配線。
- 巨大スキーマ時のキャッシュ blob サイズ・eviction は許容（再取得可能）。必要ならデータセット単位キー分割（ADR 0001）。
