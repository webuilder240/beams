# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## AgentTeam 運用

複数エージェント（マネージャー + Coder + Tester + Reviewer）で開発するときは **[docs/AGENT_TEAM.md](docs/AGENT_TEAM.md)** を唯一の正の運用規約とする（必要なときに参照）。

## コーディングの制約条件（必読）

実装時は以下を必ず守ること。各タスクの「完了」はこれらを満たすことを含む。

1. **TDD で実装する**（Red → Green → Refactor）。先に失敗するテスト（Minitest）を書き、それを通す最小実装を行い、その後リファクタする。テストを後追いで書かない。
2. **テストが通過するまでタスクを完了にしない**。完了の定義 = 対象の Minitest が green、かつ既存テストを壊していない。
3. **service クラス／`app/services` ディレクトリを作らない（禁止）**。`*Service` という命名も使わない。ドメインロジックの置き場所は次のいずれか:
   - 関連する **Active Record モデルのメソッド**（例: `Connection#bigquery`, `Query#bound_sql`）
   - **PORO を `app/models/` 配下に置く**（例: `app/models/dry_run.rb`、テストは `test/models/`）
   - 運用スクリプト（バックアップ等）は **`lib/` 配下のモジュール＋rake/`bin` ラッパー**（テストは `test/lib/`）
4. **SimpleCov カバレッジ 85% 以上を維持する**（`test/test_helper.rb` の閾値を 85% に設定）。

## Commands

### ローカル CI（PR 前に必須）
```bash
bin/ci                          # ローカルで CI 全ジョブを実行（scan_ruby / scan_js / lint / test / system-test）
bin/ci lint                     # 個別ジョブのみ実行（scan_ruby / scan_js / lint / test / system のいずれか）
BEAMS_CI_SIGNOFF=1 bin/ci       # 完走時に gh signoff を呼ぶ（commit status `signoff` を success で付与）
```

GitHub Actions の CI は `pull_request` トリガを撤去済み（コスト・待ち時間削減のため）。PR を出す前にローカルで `bin/ci` を通すことが前提。`BEAMS_CI_SIGNOFF=1` を export しておくと完走時に [`gh signoff`](https://github.com/basecamp/gh-signoff) が走り、Branch Protection で `signoff` status を必須化していればローカル CI を回さない PR がマージできない仕組みになる（個別ジョブ実行時には signoff は付かない）。

### テスト
```bash
bin/rails test                                   # 全テスト（Minitest、CPU コア数で自動並列）
bin/rails test test/models/foo_test.rb           # 単一ファイル
bin/rails test test/models/foo_test.rb:42        # 特定行
PARALLEL_WORKERS=1 bin/rails test                # シリアル実行（並列でしか出ない不具合の調査用）
SKIP_COVERAGE_CHECK=1 bin/rails test test/system # SimpleCov 閾値チェックを無効化（部分実行時）
```

テストフレームワークは **Minitest**（gem 追加なし、Rails 標準）。`test/test_helper.rb` で `parallelize(workers: :number_of_processors)` により CPU コア数で自動並列実行。FactoryBot は撤廃し、`test/support/test_data.rb` の TestData ヘルパー（`create_user` 等）と `test/fixtures/*.yml` を併用。詳細は [docs/MINITEST_MIGRATION.md](docs/MINITEST_MIGRATION.md) 参照。

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

### リリース（ghcr.io への multi-arch push）
```bash
bin/release login    # 初回のみ。gh auth refresh -h github.com -s write:packages 済みのトークンで docker login
bin/release setup    # 初回のみ。QEMU (binfmt) + buildx builder 'beams-builder' を作成
bin/release          # multi-arch (linux/amd64, linux/arm64) build + push（main + clean tree 必須）
bin/release build    # ローカル Docker に linux/amd64 のみロード（push しない確認用）
```

通常リリースは `.github/workflows/release.yml`（main push 起動）が担う。`bin/release` は GitHub Actions が詰まっているときや手元から緊急に上書きしたいとき用の同等手段。push 先イメージ・プラットフォーム・キャッシュディレクトリは `BEAMS_RELEASE_*` 環境変数で上書き可能（`bin/release --help` 参照）。

## アーキテクチャ

**Rails 8.1.3 / Ruby 4.0.5**。リポジトリ名は `sample_sns_service`（アプリケーションモジュール名も `SampleSnsService`）だが、**実体は BigQuery 専用 BI ツール「Beams」**（Redash 後継）。方針は `docs/PRODUCT_PLAN.md`、機能ごとの進行状況は `docs/tasks/`、設計判断は `docs/adr/` を参照。

### ドメインモデル
中心は「BigQuery への接続 → クエリ実行 → 可視化 → ダッシュボード集約」の流れ。サービスクラス禁止のため、ドメインロジックは AR モデルのメソッドか `app/models/` 配下の PORO に置かれている。

- `Bigquery::Connection` — BigQuery 接続情報（認証情報・プロジェクト）。`Query` の実行基盤。
- `Query` → `QueryParameter`（パラメータ化クエリ）/ `QueryExecution`（実行履歴）/ `Visualization`（可視化、has_one）。`belongs_to :user`, `belongs_to :bigquery_connection`。
- `Dashboard` → `Widget`（`belongs_to :query`）でクエリ結果をダッシュボードに配置。
- `DryRun` / `CostEstimate` — クエリ実行前のスキャン量見積もり・コスト保護用 PORO（`LimitExceededError` で上限超過を表現）。
- `ApplicationSetting` — アプリ全体設定（セットアップウィザードで構築）。

### 運用スクリプト（バックアップ/リストア）
SQLite DB のバックアップ・リストアは `lib/beams/`（`backup.rb` / `restore.rb` / `procfile_reader.rb`）のモジュール + `lib/tasks/beams.rake` のラッパーで提供（`rake beams:backup`, `beams:backup:list`, `beams:restore[generation]`）。手順は `docs/RESTORE.md`。テストは `test/lib/`。

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
ONCE プラットフォーム（[basecamp/once](https://github.com/basecamp/once)）で配布する。設置手順は `docs/INSTALL.md` を参照。

### テスト構成
- **Minitest**（Rails 標準、gem 追加なし）+ **fixtures** + **TestData ヘルパー**（`test/` 以下）
- `test/support/` 以下のファイルは `test/test_helper.rb` から自動読み込み
- `test/support/test_data.rb` の TestData ヘルパー（`create_user`, `create_query`, `create_bigquery_connection` 等）を `ActiveSupport::TestCase` に include 済み。FactoryBot は撤廃
- **SimpleCov** がカバレッジを計測（`test/test_helper.rb` で設定）
- 並列実行は Rails 標準の `parallelize(workers: :number_of_processors)` を `test_helper.rb` で有効化（gem 追加なし）。SQLite では worker ごとに `storage/test-<id>.sqlite3` が自動分離される
- minitest 6 では `Object#stub` が標準で提供されないため、`test_helper.rb` で互換実装を入れている（`x.stub(:m, v) { ... }` 形式）
- System test は `test/system/` 配下。`test/application_system_test_case.rb` で `ApplicationSystemTestCase`（`rack_test`）と `ApplicationJsSystemTestCase`（Playwright）の 2 つの基底クラスを定義。JS が必要な test は後者を継承
- ローカルで Playwright を初回実行する前に `npx playwright install chromium` が必要


### CI（GitHub Actions）
`pull_request` トリガは撤去済み。`push: main` と `workflow_dispatch` のみで動作する（`.github/workflows/ci.yml`）。PR 前は `bin/ci` でローカル実行して green を確認すること。`BEAMS_CI_SIGNOFF=1` を設定して `bin/ci` を回すと完走時に `gh signoff` で commit status `signoff` が success として付与される。Branch Protection（main）で `signoff` を必須化しておけば、ローカル CI を回していない PR はマージできなくなる（運用手順は `docs/INSTALL.md` 「開発者向けセットアップ」参照）。万一ローカルで通し忘れても main push 時に同じ 5 ジョブが並列実行される保険として残してある：
1. `scan_ruby` — Brakeman + bundler-audit
2. `scan_js` — importmap audit
3. `lint` — RuboCop（`bin/rubocop -f github`）
4. `test` — `bin/rails db:test:prepare && bin/rails test`（Minitest、CPU コア数で並列実行）
5. `system-test` — `bin/rails test test/system`（Playwright browsers + `tailwindcss:build` を事前実行。失敗時スクリーンショットをartifactに保存）
