# トピック28 — ローカル CI 化（`bin/ci`）と PR トリガ撤去（進捗ログ）

> 関連タスク: [docs/tasks/28-local-ci.md](../28-local-ci.md)
> 担当: Coder（マネージャー直依頼・単発）
> 着手: 2026-06-06

## 決定事項（着手前にボス確定済み）

- `pull_request` トリガを撤去し、PR ごとの GitHub Actions CI 実行を止める。
- `push: branches: [main]` と `workflow_dispatch:` だけ残す。
- `bin/ci` を薄いシェルラッパーに置き換え、`.github/workflows/ci.yml` の 5 ジョブと等価のコマンド列を順次実行する。
- 旧 `bin/ci`（Rails 8 の `ActiveSupport::ContinuousIntegration` を使う Ruby スクリプト）は上書きする。

## 実装ログ（時系列）

### 1. 既存状態の把握

- 旧 `bin/ci` は `ActiveSupport::ContinuousIntegration` 経由で `config/ci.rb` を読み込む Ruby スクリプトだった。`bin/rails test` を呼んでいて、本プロジェクトの RSpec / system spec / SimpleCov 構成とは噛み合っていない（`bin/rails test` は実体上 Minitest 起動になりカバレッジ閾値も拾えない）。
- `.github/workflows/ci.yml` は 5 ジョブ（`scan_ruby` / `scan_js` / `lint` / `test` / `system-test`）並列。`on:` は `pull_request:` と `push: branches: [main]`。
- ローカルラッパーは ci.yml の 5 ジョブと完全一致させる方針で書き直す。

### 2. `bin/ci` をシェルラッパーに置き換え

- `#!/usr/bin/env bash` + `set -euo pipefail`。
- 引数なしで 5 ジョブ順次、引数指定（`scan_ruby` / `scan_js` / `lint` / `test` / `system` / `system-test`）で個別実行。
- `==> [N/5] <job>` 形式の進捗ログを stdout に出力。最後に `==> all green`。
- `chmod 755 bin/ci`。

### 3. `.github/workflows/ci.yml` のトリガ変更

- `on:` ブロックから `pull_request:` を削除。
- `push: branches: [main]` は据え置き。
- `workflow_dispatch:` を追加。
- 5 ジョブ本体は無変更。

### 4. `CLAUDE.md` 更新

- `## Commands` セクションの先頭に「ローカル CI（PR 前に必須）」を追加。
- 「CI（GitHub Actions）」節を「`pull_request` トリガは撤去。`push: main` と `workflow_dispatch` のみ。PR 前は `bin/ci` でローカル実行する」と書き直し（5 ジョブの内訳は保持）。

### 5. タスク文書

- `docs/tasks/28-local-ci.md` を新設。
- `docs/tasks/00-overview.md` と `docs/tasks/PROGRESS_LOG.md` の表にトピック28 行を追加。

### 6. 動作確認（`time bin/ci` フル実行）

- 結果は本コミット作成時にマネージャーへ返却。
