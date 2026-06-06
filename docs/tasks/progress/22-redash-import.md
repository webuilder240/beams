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
