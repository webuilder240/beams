# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## AgentTeam 運用（複数エージェントで開発するとき必読）

複数エージェント（司令塔 + Coder + Tester + Reviewer）で開発する場合は **[docs/AGENT_TEAM.md](docs/AGENT_TEAM.md)** を唯一の正の運用規約とする。スラッシュコマンド `/breakdown`（タスク分解）・`/agent-team`（実行）と `reviewer` スキルがこれに従う。要点: 司令塔は実装しない（実装は必ず Coder）／直列実行・並行起動しない／実装は専用ブランチ＋worktree隔離／報告を鵜呑みにせず実測検証・偽の数値禁止／DBマイグレーションとPR作成・マージは承認ゲート。

## コーディングの制約条件（必読）

実装時は以下を必ず守ること。各タスクの「完了」はこれらを満たすことを含む。

1. **TDD で実装する**（Red → Green → Refactor）。先に失敗するテスト（RSpec）を書き、それを通す最小実装を行い、その後リファクタする。テストを後追いで書かない。
2. **テストが通過するまでタスクを完了にしない**。完了の定義 = 対象の RSpec が green、かつ既存テストを壊していない。
3. **service クラス／`app/services` ディレクトリを作らない（禁止）**。`*Service` という命名も使わない。ドメインロジックの置き場所は次のいずれか:
   - 関連する **Active Record モデルのメソッド**（例: `Connection#bigquery`, `Query#bound_sql`）
   - **PORO を `app/models/` 配下に置く**（例: `app/models/dry_run.rb`、テストは `spec/models/`）
   - 運用スクリプト（バックアップ等）は **`lib/` 配下のモジュール＋rake/`bin` ラッパー**（テストは `spec/lib/`）
4. **SimpleCov カバレッジ 85% 以上を維持する**（`spec/spec_helper.rb` の閾値を 85% に設定）。

## Commands

### テスト
```bash
bundle exec rspec                        # 全テスト実行（SimpleCovカバレッジ計測付き）
bundle exec rspec spec/models/foo_spec.rb  # 単一ファイルのテスト
bundle exec rspec spec/models/foo_spec.rb:42  # 特定の行のテスト
```

カバレッジは **85%** 未満でエラー終了（exit code 2）。レポートは `coverage/index.html` に生成される。

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
