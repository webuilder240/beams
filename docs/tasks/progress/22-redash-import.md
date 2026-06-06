# トピック22 実装ログ: Redash クエリ取り込み（API版）

## 実装日時
2026-06-06

## ブランチ
`feat/22-redash-import`（base: main `a549b76`）

## 実装方針
- B1〜B8 確定済み（22-redash-import.md 表参照）
- マイグレーション: ボス承認済み（2026-06-06）
- TDD（Red → Green → Refactor）
- service クラス禁止 — PORO を `app/models/` 配下に置く

## 時系列ログ

### 2026-06-06

#### 1. Gem 追加（webmock）
- `Gemfile` の `group :test do` に `gem "webmock", require: false` を追加
- `bundle install`: webmock 3.26.2 / crack 1.0.1 / hashdiff 1.2.1 が追加された
- `spec/rails_helper.rb` に `require "webmock/rspec"` と `WebMock.disable_net_connect!(allow_localhost: true)` を追加
- `bin/bundler-audit check`: クリーン（No vulnerabilities found）

#### 2. マイグレーション（redash_sources）
- `db/migrate/20260606103507_create_redash_sources.rb` 作成（name/url/api_key/timestamps、name に unique index）
- `bin/rails db:migrate`: 成功
- `bin/rails db:rollback STEP=1`: 成功（drop_table 確認）
- 再度 `bin/rails db:migrate`: 成功
- `bin/rails db:test:prepare`: 成功
- `db/schema.rb` に `redash_sources` テーブル定義が反映済み

#### 3. RedashSource モデル + 暗号化 + SSRF 共通ガード
- 先に `spec/models/redash_source_spec.rb` を Red で作成（16 examples）
- `app/models/redash_source.rb` 実装:
  - `encrypts :api_key`（AR Encryption）
  - presence/uniqueness バリデーション
  - クラスメソッド `RedashSource.guard_url!(url)` で SSRF ガード（https のみ、ホスト解決後の IP を FORBIDDEN_RANGES と突き合わせ）
  - `RedashClient` 側からも同じ `guard_url!` を呼び出す（リクエスト直前に二重チェック）
- `app/models/redash_client.rb` の例外クラス（`Error`/`Unauthorized`/`NotFound`/`ServerError`/`Timeout`/`ForbiddenURLError`）も同コミットで定義（バリデーションから参照されるため）
- スペック: 16/16 green（暗号文確認・正常 IP・privateIP/loopback/metadata 拒否・スキーム拒否を網羅）

#### 4. RedashClient PORO + SSRF ガード + WebMock スペック
- `spec/factories/redash_sources.rb` 追加
- `spec/models/redash_client_spec.rb` を Red で作成（13 examples、`#list_queries` / `#fetch_query` の正常系・401/403/404/5xx/Timeout・JSON パース失敗・SSRF ガード loopback/private/link-local/解決失敗）
- `app/models/redash_client.rb` を完成:
  - Net::HTTP 直使用、`Authorization: Key <api_key>` ヘッダ
  - リクエスト直前に `RedashSource.guard_url!` を呼ぶ
  - タイムアウト 5s（open/read）、リダイレクト追従なし
  - 200 → JSON パース、401/403 → Unauthorized、404 → NotFound、5xx → ServerError、タイムアウト → Timeout、JSON パース失敗 → ServerError
- スペック: 13/13 green。SSRF テストでは WebMock スタブが「リクエストされていない」ことを `expect(stub).not_to have_been_requested` で確認（実 HTTP が送られないこと）
