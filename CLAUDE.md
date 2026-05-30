# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Commands

### テスト
```bash
bundle exec rspec                        # 全テスト実行（SimpleCovカバレッジ計測付き）
bundle exec rspec spec/models/foo_spec.rb  # 単一ファイルのテスト
bundle exec rspec spec/models/foo_spec.rb:42  # 特定の行のテスト
```

カバレッジは90%未満でエラー終了（exit code 2）。レポートは `coverage/index.html` に生成される。

### Lint
```bash
bin/rubocop            # スタイルチェック
bin/rubocop -a         # 自動修正
bin/rubocop -A         # 危険な自動修正を含む
```

スタイルルールは `rubocop-rails-omakase` に準拠。

### セキュリティスキャン
```bash
bin/brakeman --no-pager   # Rails静的解析
bin/bundler-audit          # gem脆弱性チェック
bin/importmap audit        # JS依存脆弱性チェック
```

### DB操作
```bash
bin/rails db:migrate
bin/rails db:test:prepare  # テスト用DBをschema.rbから再構築
```

## アーキテクチャ

**Rails 8.1.3 / Ruby 4.0.5** のSNSサービス。アプリケーションモジュール名は `SampleSnsService`。

### Solid Stack（SQLite完結構成）
本番環境は単一インフラ（Docker + SQLite）で動作する。4つのSQLiteデータベースを用途別に分離している：

| DB | 用途 | マイグレーションパス |
|----|------|---------------------|
| `storage/production.sqlite3` | メインデータ | `db/migrate` |
| `storage/production_cache.sqlite3` | `solid_cache` | `db/cache_migrate` |
| `storage/production_queue.sqlite3` | `solid_queue` | `db/queue_migrate` |
| `storage/production_cable.sqlite3` | `solid_cable` | `db/cable_migrate` |

開発・テスト環境は `storage/development.sqlite3` / `storage/test.sqlite3` のみ使用。

### デプロイ
Kamal を使用。`config/deploy.yml` を参照。

### テスト構成
- **RSpec** + **FactoryBot** + **Faker**（`spec/` 以下）
- `spec/support/` 以下のファイルは自動読み込み済み
- `spec/support/factory_bot.rb` でFactoryBotのDSL（`create`, `build` 等）をそのまま使用可能
- **SimpleCov** がカバレッジを計測（`spec/spec_helper.rb` で設定）
- System Specは `spec/system/` 以下に配置する。**原則JSなし**（`rack_test` ドライバー）で作成する
- JSが必要な場合（リグレッションテストなど）のみ `js: true` メタデータを付与してPlaywright（chromium）で実行する。ローカルで初回実行前に `npx playwright install chromium` が必要


### CI（GitHub Actions）
PRおよびmainへのpushで以下が並列実行される：
1. `scan_ruby` — Brakeman + bundler-audit
2. `scan_js` — importmap audit
3. `lint` — RuboCop
4. `test` — Minitest
5. `system-test` — システムテスト（失敗時スクリーンショットをartifactに保存）
