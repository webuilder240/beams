# トピック28: ローカル CI 化（`bin/ci`）と PR トリガ撤去

> GitHub Actions の CI を「PR ごと並列実行」から「`bin/ci` でローカル実行 + main push の保険」に切り替える。
> コスト・待ち時間を抑えることが目的。計画書には明示されていない運用品質向上トピック。

- **ステータス**: 進行中（2026-06-06 分解 → 同日実装）
- **依存**: なし（CI 設定とシェルスクリプトのみ。Ruby コードの変更はない）
- **関連計画書**: 該当なし（運用品質向上）

---

## 背景

GitHub Actions の CI（`.github/workflows/ci.yml`）は PR ごと・main push ごとに 5 ジョブ並列実行している。

- 1 PR で 5 ジョブ × 平均数分の CI 時間を消費する。
- PR の小さな修正ごとに走るとコスト・待ち時間が積み上がる。
- 開発体験として「push → CI 結果待ち」が長い。

そこで PR トリガを撤去し、開発者がローカルで `bin/ci` を叩いて自己責任で green を確認する運用に切り替える。`main` への push と手動実行（`workflow_dispatch`）だけは GitHub Actions 側に残し、「ローカルでうっかり通し忘れて main に流入する」事故を main 側で拾えるようにする。

---

## 変更内容

### 1. `bin/ci`（新規・上書き）

旧 `bin/ci` は Rails 8 の `ActiveSupport::ContinuousIntegration` を使う Ruby スクリプトだったが、本プロジェクトでは `.github/workflows/ci.yml` のジョブ構成と完全一致させたいため、薄いシェルラッパーに置き換える。

- `#!/usr/bin/env bash` shebang、`set -euo pipefail`
- 実行順は ci.yml に揃える:
  1. `scan_ruby`: `bin/brakeman --no-pager` → `bin/bundler-audit`
  2. `scan_js`: `bin/importmap audit`
  3. `lint`: `bin/rubocop`（`-f github` は GitHub Actions 用フォーマットなのでローカルでは外す）
  4. `test`: `bin/rails db:test:prepare && bin/rails tailwindcss:build && bundle exec rspec --exclude-pattern "spec/system/**/*_spec.rb"`
  5. `system-test`: `SKIP_COVERAGE_CHECK=1 bundle exec rspec spec/system`（`db:test:prepare` と `tailwindcss:build` は test ジョブで実行済みのため省略。1 度の `bin/ci` 内では再実行しない）
- ジョブ単位でプレフィックス付き進捗を表示（`==> [N/5] <job_name>`）。
- 失敗で即終了、最後に `==> all green` を表示。
- 引数で個別ジョブだけ実行できる: `bin/ci scan_ruby` / `scan_js` / `lint` / `test` / `system`（`system-test` の別名）。引数なしで全ジョブ。
- 実行権限 `755` でコミット。

### 2. `.github/workflows/ci.yml`（トリガ変更）

- `on:` ブロックから `pull_request:` を削除。
- `push: branches: [main]` は残す。
- `workflow_dispatch:` を追加（手動実行を可能に）。
- ジョブの中身（`scan_ruby` / `scan_js` / `lint` / `test` / `system-test`）は触らない。万一の main push 時の保険として等価に残す。

### 3. `CLAUDE.md`（更新）

- `## Commands` セクションに `bin/ci` のエントリを追加。
- 「CI（GitHub Actions）」節を簡潔に更新し、「`pull_request` トリガは撤去。`push: main` と `workflow_dispatch` のみ。PR 前は `bin/ci` でローカル実行する」旨を明記。

### 4. タスク文書（本ファイル + 索引）

- `docs/tasks/28-local-ci.md`（本ファイル）。
- `docs/tasks/progress/28-local-ci.md` に時系列ログを追加。
- `docs/tasks/00-overview.md` / `docs/tasks/PROGRESS_LOG.md` にトピック28 行を追加。

---

## 受け入れ条件

- `bin/ci` が実行権限 `755` を持ち、引数なしで 5 ジョブを順次実行して `==> all green` を出力する。
- `bin/ci lint` 等で個別ジョブのみ実行できる。
- `.github/workflows/ci.yml` の `on:` ブロックが `push: branches: [main]` と `workflow_dispatch:` の 2 つのみで、`pull_request:` を含まない。
- ジョブ定義（`scan_ruby` / `scan_js` / `lint` / `test` / `system-test`）は内容変更なし。
- `CLAUDE.md` に `bin/ci` の使い方と新しい CI トリガの説明が反映されている。
- `bin/rubocop` clean。既存 RSpec を壊していない（`bin/ci` フル実行で確認）。

---

## 厳守

- PR トリガ撤去で **PR ごとの CI が走らなくなる**ことに合意済み。
- 偽の数値・ハッシュは書かない。
- service クラス禁止は引き続き遵守（今回 Ruby コードの追加はない）。
