# トピック22: Redash クエリ取り込み（Redash API 経由）

> Redash サーバーに接続情報（URL + APIキー）を設定しておき、Beams が Redash REST API を直接叩いて
> 「クエリ一覧の取得」と「複数クエリの一括取り込み」を行う。
> 計画書 §7「Redash SQLインポート（クエリ本文＋タイトルの最小移行、パラメータ記法変換）」に対応。
> パラメータ記法 `{{ name }}` は Redash と Beams で同一なので**変換不要**。型のマッピングだけ行う。

- **ステータス**: **実装完了（2026-06-06、`feat/22-redash-import`）**。マイグレーション承認済み・全タスク green・カバレッジ 98.01%。
- **依存**: [[07-query-editor]]（`Query`・`QueryParameter`・`sync_parameters!`）/ [[04-bigquery-connection]]（接続選択UI・Active Record Encryption の前例）/ [[03-auth-users]]（所有者・admin認可）
- **関連計画書**: §7（将来項目を一部実装）

---

## ボス決定事項（**全項目確定 2026-06-06**）

> 2026-06-06 にユーザー指示で「JSONペースト方式」から「Redash API 直接呼び出し方式」へ全面変更。B2/B3 を書き換え、B8 を新設。

| ID | 決定内容 |
|---|---|
| **B1** ✅ | **Redash 公式 REST API**（`GET /api/queries` で一覧、`GET /api/queries/:id` で詳細）。レスポンスは公式JSON形式 |
| **B2** ✅ | **Redash接続情報を保存する**。新モデル `RedashSource`（URL + 暗号化APIキー + 名前）を作る。`Bigquery::Connection.service_account_json` と同じ **Active Record Encryption** 方式で APIキーを保管 |
| **B3** ✅ | **クエリ一覧画面で複数選択して一括取り込み**。RedashSource を選ぶと Redash 上のクエリ一覧を取得・表示、チェックボックスで複数選び、BigQuery接続を指定して一括 import |
| **B4** ✅ | 未対応typeは**警告付き `string` フォールバックで取り込み続行**（拒否しない）。型マッピング表は下記 |
| **B5** ✅ | 所有者=**ログイン中ユーザー**、接続=**インポート画面でBigQuery接続を必須選択**（Redashの`data_source_id`は無視） |
| **B6** ✅ | **インポート由来情報は保持しない**（`queries.imported_from` カラム追加なし） |
| **B7** ✅ | **Redash拡張記法は警告のみ、SQL本文はそのまま保存**（手動修正前提） |
| **B8** ✅ | **SSRF対策は「基本ガード」レベル**: HTTPS強制、private IP/loopback/metadata endpoint をブロック、タイムアウト5秒 |

### B4 詳細: パラメータ型マッピング表

| Redash type | Beams にマップ | 備考 |
|---|---|---|
| `text` | `string` | ✅ そのまま |
| `number` | `number` | ✅ そのまま |
| `date` | `date` | ✅ そのまま |
| `date-range` | `date_range` | ✅ そのまま |
| `datetime-local` / `datetime-with-seconds` | `string`（警告） | ⚠️ Beams未対応精度。手動調整前提 |
| `datetime-range` / `datetime-range-with-seconds` | `date_range`（警告） | ⚠️ 時刻情報は捨てる |
| `enum` | `string`（警告） | ⚠️ Beamsにdropdown未実装 |
| `query`（動的dropdown） | `string`（警告） | ⚠️ Beams未対応 |
| 未知の type | `string`（警告） | ⚠️ フォールバック |

警告は `RedashQueryPayload#warnings` で配列として返し、インポート結果画面に表示する。

### B7 詳細: 拡張記法の検出対象

| Redash 拡張 | 扱い |
|---|---|
| `{{ name }}` | そのまま（同一記法・変換不要） |
| `{{ "x" \| param_name }}`（フィルタ式） | 検出して**警告**、SQL本文はそのまま保存 |
| `{% if %}` 等のテンプレートタグ | 検出して**警告**、そのまま保存 |

### B8 詳細: SSRF対策チェック項目

`RedashSource` 作成時・各APIリクエスト前に以下をチェック:

1. **スキーム**: `https` のみ許可（`http`/`file`/`ftp`/`gopher` は拒否）
2. **ホスト名解決後のIP**: 以下を拒否
   - loopback: `127.0.0.0/8`, `::1`
   - private: `10.0.0.0/8`, `172.16.0.0/12`, `192.168.0.0/16`, `fc00::/7`
   - link-local: `169.254.0.0/16`, `fe80::/10`（AWS/GCPメタデータエンドポイント含む）
   - multicast / broadcast
3. **タイムアウト**: open_timeout 5s, read_timeout 5s
4. **リダイレクト**: 自動追従しない（明示的に1リクエスト = 1接続）

実装は `app/models/redash_source.rb` のバリデーション + `RedashClient` PORO 内のリクエスト直前ガードで二重に行う。

---

## ゴール（完了の定義）

- admin が `/admin/redash_sources` で `RedashSource`（名前・URL・APIキー）の CRUD ができる
- APIキーは Active Record Encryption で暗号化保存される（`Bigquery::Connection.service_account_json` と同方式）
- ログイン中ユーザーが `/redash_imports/new` で:
  1. `RedashSource` を選ぶ
  2. Beams が Redash API `GET /api/queries` を叩いてクエリ一覧を取得・表示
  3. チェックボックスで複数クエリを選択
  4. BigQuery接続を選び、「取り込み実行」を押す
  5. Beams が各クエリについて `GET /api/queries/:id` を叩いて詳細を取得 → `RedashQueryPayload` で解析 → `Query` / `QueryParameter` を作成
  6. 結果画面に「成功N件 / 失敗M件 + 各クエリの警告」を表示
- `RedashQueryPayload` の解析ロジックはJSONペースト案と同じものを再利用
- SSRF対策（B8）が全リクエストに適用される
- Redash API への接続失敗・認証失敗・タイムアウトはユーザーに分かりやすいエラーメッセージで戻す
- DB変更: `redash_sources` テーブル新規（要マイグレーション承認）
- RSpec が通り、SimpleCov 85% 以上を維持

---

## 前提・参照（実読済み）

- `app/models/query.rb` — `PARAMETER_PATTERN = /\{\{\s*([a-zA-Z_]\w*)\s*(?::\s*(\w+)\s*)?\}\}/`、`after_save :sync_parameters!`。
- `app/models/query_parameter.rb` — `SUPPORTED_TYPES = %i[string number date date_range]`。
- `app/models/bigquery/connection.rb` — `service_account_json` を Active Record Encryption で暗号化保存している前例。同じパターンを `RedashSource.api_key` に流用。
- `Query` は `belongs_to :user`、`belongs_to :bigquery_connection` 必須。
- Redash API レスポンスフォーマット:
  - 一覧: `GET /api/queries?page=N&page_size=N` → `{ "count": N, "page": N, "page_size": N, "results": [{"id":..., "name":..., "data_source_id":..., ...}, ...] }`
  - 詳細: `GET /api/queries/:id` → `{ "id":..., "name":..., "query":..., "options": {"parameters": [...]}, ... }`
- 認証: `Authorization: Key <api_key>` ヘッダ（または `?api_key=<key>` クエリパラメータ）

---

## タスク

### DBマイグレーション（事前承認ゲート）

- [x] **`docs/tasks/migrations/22-redash-sources-migration.md` を作成し、ボス承認を取る**。内容: `redash_sources` テーブル新規（name / url / api_key / timestamps）。
- [x] 承認後マイグレーション作成・実行（`db/migrate/YYYYMMDDHHMMSS_create_redash_sources.rb`）
  - 受け入れ条件: `bin/rails db:migrate` 成功・`db:rollback` 成功。`db/schema.rb` 反映。

### RedashSource モデル

- [x] `app/models/redash_source.rb` 新規作成
  - `validates :name, :url, :api_key, presence: true`
  - `validates :name, uniqueness: true`
  - URL バリデーション: HTTPSスキーム必須、ホスト名解決可能（クラスメソッドでなくバリデータ実装は B8 の `RedashClient` 側に共通化）
  - `encrypts :api_key`（Active Record Encryption）
  - 受け入れ条件: モデルスペック green（`spec/models/redash_source_spec.rb`）。
    - 正常な https URL を受け付ける
    - http / file スキームを拒否
    - 名前空欄・重複を拒否
    - `api_key` が暗号化されて保存される（`SELECT api_key FROM redash_sources` で平文が出ない）

### RedashClient PORO（API呼び出し + SSRF ガード）

> service クラス禁止のため、PORO として `app/models/` 配下に置く。

- [x] `app/models/redash_client.rb` 新規作成
  - コンストラクタ: `RedashClient.new(redash_source)`
  - パブリック API:
    - `#list_queries(page:, page_size:)` — `GET /api/queries`、ページネーション込み
    - `#fetch_query(id)` — `GET /api/queries/:id`
  - 内部: Net::HTTP 直使用（Gem追加なし）。`Authorization: Key <api_key>` ヘッダ。
  - **SSRF ガード**: `#fetch_query` / `#list_queries` のリクエスト直前に URL のIPを `Resolv` で解決して B8 の禁止帯域をチェック、該当なら `RedashClient::ForbiddenURLError` を raise。
  - タイムアウト: `open_timeout=5, read_timeout=5`、リダイレクト追従しない
  - 失敗種別を例外クラスで明示: `Unauthorized`/`NotFound`/`ServerError`/`Timeout`/`ForbiddenURLError`
  - 受け入れ条件: `spec/models/redash_client_spec.rb` で全パスを WebMock スタブで検証（gem `webmock` 追加が必要なら Gemfile に追加）。
    - 正常な一覧取得
    - 正常な詳細取得
    - 401 → `Unauthorized` raise
    - 404 → `NotFound` raise
    - 5xx → `ServerError` raise
    - タイムアウト → `Timeout` raise
    - private IP（127.0.0.1/10.x/169.254.169.254）への接続試行 → `ForbiddenURLError` raise（実HTTPは送られないこと）

### RedashQueryPayload PORO（解析・既存設計を流用）

- [x] `app/models/redash_query_payload.rb` 新規作成 — **JSONペースト案と同じインターフェース**。`new(hash)` で Redash API レスポンスを直接受ける（パース済みのHashを渡す）。
  - `#valid?` / `#errors` / `#title` / `#sql_body` / `#parameters` / `#warnings`
  - B4 の型マッピング・B7 の拡張記法検出をここで行う
  - 受け入れ条件: `spec/models/redash_query_payload_spec.rb` で全マッピング・警告ケースを検証 green。

### コントローラ（admin: RedashSource CRUD）

- [x] `app/controllers/admin/redash_sources_controller.rb` を新規作成 — index / new / create / edit / update / destroy
  - `before_action :require_admin`
  - `config/routes.rb` の `namespace :admin do ... end` に `resources :redash_sources` を追加
  - 受け入れ条件: リクエストスペックで admin が CRUD でき、member は弾かれる。

### コントローラ（インポート本体）

- [x] `app/controllers/redash_imports_controller.rb` を新規作成
  - `new` — `RedashSource` 選択フォーム
  - `index_queries` — `params[:redash_source_id]` を受け、`RedashClient#list_queries` を叩いて取得した一覧を表示（チェックボックス + BigQuery 接続選択）
  - `create` — チェックされた `query_ids` 配列と `bigquery_connection_id` を受け、各IDに対して `RedashClient#fetch_query` → `RedashQueryPayload` → `current_user.queries.create!(...)` をループ実行。途中失敗しても残りを続行、結果（成功/失敗/警告）を `flash` または専用結果画面で表示。
  - 失敗時のエラー処理: `RedashClient` の例外 → ユーザー向けメッセージ（「Redashサーバに接続できません」「APIキーが無効です」など）
  - 受け入れ条件: リクエストスペックで一覧取得・取り込み成功・部分失敗・接続エラーの各分岐を検証 green。

### ルート

- [x] `config/routes.rb` を更新
  - admin 名前空間に `resources :redash_sources` 追加
  - `resource :redash_import, only: [:new, :create] do member { get :index_queries } end`（または同等の構造）
  - 受け入れ条件: `rails routes | grep redash` に admin CRUD と import 系が出る。

### ビュー

- [x] `app/views/admin/redash_sources/` の CRUD ビュー（既存 `bigquery/connections` を参考に [[16-form-styling-consistency]] のTailwindクラスで統一）
- [x] `app/views/redash_imports/new.html.erb` — `RedashSource` 選択フォーム
- [x] `app/views/redash_imports/index_queries.html.erb` — クエリ一覧（タイトル・更新日時・チェックボックス）+ BigQuery接続選択 + 「取り込み実行」ボタン
- [x] インポート結果画面（成功/失敗/警告の一覧）
- [x] クエリ一覧（`app/views/queries/index.html.erb`）に「Redashから取り込み」リンクを追加
  - 受け入れ条件: System Spec `rack_test` で一連の画面遷移と取り込み完了が検証できる。

### 警告・エラー表示

- [x] 取り込み結果画面で:
  - 成功したクエリは「[成功] <タイトル> → <Beamsのクエリへのリンク>」表示
  - 警告ありは「警告: <内容>」を箇条書き表示
  - 失敗は「[失敗] <タイトル> （エラー: <内容>）」表示
  - 受け入れ条件: 全パターンを含む System Spec で表示確認。

### テスト

- [x] `spec/models/redash_source_spec.rb` — バリデーション・暗号化
- [x] `spec/models/redash_client_spec.rb` — WebMock で API モック、SSRF ガード、エラー分岐
- [x] `spec/models/redash_query_payload_spec.rb` — JSON パース・型マッピング・警告
- [x] `spec/requests/admin/redash_sources_spec.rb` — admin CRUD・認可
- [x] `spec/requests/redash_imports_spec.rb` — 一覧・取り込み成功/部分失敗/接続エラー
- [x] `spec/system/redash_imports_spec.rb`（`rack_test`） — admin が RedashSource を登録 → ログインユーザーが一覧から複数選択して取り込み → 結果画面確認
- [x] 既存テストが壊れていない

### Gem追加

- [x] `Gemfile` の `group :test do ... end` に `webmock` を追加（HTTPスタブ用）
  - 受け入れ条件: `bundle install` 成功、`spec/rails_helper.rb` に WebMock 初期化追加。

### ドキュメント

- [x] `docs/PRODUCT_PLAN.md` §7 の該当行に「実装済み（トピック22）」を注記
- [x] `docs/tasks/progress/22-redash-import.md` を作成し時系列ログを残す

---

## 動作確認

- [x] admin が `/admin/redash_sources` で RedashSource を作成（URL https://demo.redash.io 等） — System Spec で WebMock を用いて検証
- [x] member が `/redash_imports/new` → RedashSource 選択 → クエリ一覧が表示される — System/Request Spec で検証
- [x] 複数選択して BigQuery 接続を指定 → 取り込み → 各クエリが Beams 上に作成される — System Spec で 2 件取り込み確認
- [x] パラメータ記法 `{{ start_date }}` が QueryParameter（type=date）として正しく生成される — System Spec / Request Spec の `query_parameters.pluck(:name, :param_type)` で確認
- [x] `datetime-local` を含む Redash クエリ → `string` で取り込まれ、警告が表示される — Request Spec / System Spec で検証
- [x] private IP (`http://127.0.0.1:5000` 等) で RedashSource を作ろうとする → バリデーションエラー — Model Spec で検証
- [x] 不正なAPIキーで一覧を取得 → 「APIキーが無効です」エラー — Request Spec / System Spec で検証
- [x] Redash サーバへの到達不可（タイムアウト） → 「Redashサーバに接続できません」エラー — Request Spec で検証
- [x] `bundle exec rspec` 全 green、SimpleCov 85% 以上 — 583 examples, 0 failures, Line Coverage 98.01%
- [x] `bin/rubocop` / `bin/brakeman` / `bin/bundler-audit` クリーン

---

## 未決事項・質問

なし（B1〜B8 はすべて確定済み 2026-06-06）。
マイグレーション確認ドキュメント（`docs/tasks/migrations/22-redash-sources-migration.md`）の最終承認は Coder が実行する直前にボスから取得する。
