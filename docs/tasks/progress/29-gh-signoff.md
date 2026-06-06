# トピック29 — `gh signoff` でローカル CI を強制する（進捗ログ）

> 関連タスク: [docs/tasks/29-gh-signoff.md](../29-gh-signoff.md)
> 担当: Coder（マネージャー直依頼・単発）
> 着手: 2026-06-06

## 決定事項（着手前にボス確定済み）

- `bin/ci` に `gh signoff` 呼び出しを追加するが、**オプトイン**（`BEAMS_CI_SIGNOFF=1`）に留める。デフォルト挙動は変えない。
- 全ジョブ実行（引数なし）のときのみ signoff を呼ぶ。個別ジョブ（`bin/ci lint` 等）では signoff しない。
- `gh` CLI / `gh-signoff` extension が未インストールの場合は STDERR に明確なエラーを出して `exit 1`。
- `docs/INSTALL.md` に「## 11. 開発者向けセットアップ（オプション）」節を新設し、`gh` インストール → `gh extension install basecamp/gh-signoff` → `BEAMS_CI_SIGNOFF=1` を shell rc に export → Branch Protection 設定の手順を載せる。

## 実装ログ（時系列）

### 1. 既存状態の把握

- `bin/ci` はトピック28 で薄いシェルラッパー（`#!/usr/bin/env bash` + `set -euo pipefail`）に置き換え済み。引数なしで 5 ジョブを順次実行し、`==> all green` を出力して exit 0。
- `BEAMS_CI_SIGNOFF` 系の環境変数は未使用。`gh` CLI / `gh-signoff` extension への参照もリポジトリ内に無い。
- `docs/INSTALL.md` は §1〜§10 で本番設置中心の構成。開発者向け節は存在しない。

### 2. `bin/ci` に signoff 関数を追加

- `run_signoff()` を新設し、`BEAMS_CI_SIGNOFF != 1` のときは即 return。
- `command -v gh` が無ければ STDERR に「gh CLI が見つかりません」とインストール URL を出力して `exit 1`。
- `gh extension list` の出力に `basecamp/gh-signoff` が含まれていなければ STDERR に「gh signoff extension が未インストール」と `gh extension install basecamp/gh-signoff` を案内して `exit 1`。
- 揃っていれば `==> signoff (gh signoff)` を出力し、`gh signoff` を実行（`set -e` 配下なので失敗時は exit code 伝播）。
- 呼び出しは「引数なし全ジョブ完走時 → `==> all green` 出力後」だけ。個別ジョブの `case` 分岐側では呼ばない。
- `usage()` の末尾に `ENV: BEAMS_CI_SIGNOFF=1` のヒントを追加。

### 3. `docs/INSTALL.md` 更新

- 「## 11. 開発者向けセットアップ（オプション）」を新設。
- 11.1 `gh signoff` でローカル CI を強制する:
  - 個人開発者向けセットアップ（gh CLI / gh auth login / `gh extension install basecamp/gh-signoff` / `BEAMS_CI_SIGNOFF=1` を shell rc に export）
  - 「`bin/ci` 完走時に自動で `signoff` commit status が付くため、Branch Protection で必須化すればローカル飛ばし防止になる」と運用効果を 1 行で明記
  - リポジトリ管理者向け Branch Protection 設定の箇条書き手順（Settings → Branches → Add rule → `main` → Require status checks → `signoff`）

### 4. `CLAUDE.md` 更新

- `## Commands` の `bin/ci` ブロックに `BEAMS_CI_SIGNOFF=1 bin/ci  # 完走時に gh signoff を呼ぶ` を追記。ローカル CI 説明文に「Branch Protection で `signoff` status を必須化していればローカル CI を回さない PR がマージできない仕組みになる」と運用効果を併記。
- 「CI（GitHub Actions）」節に「`gh signoff` を使うと commit status `signoff` が付く。Branch Protection で必須化すればローカル CI 経由マージを強制できる（運用手順は `docs/INSTALL.md` 「開発者向けセットアップ」参照）」を 1 文追加。

### 5. タスク文書

- `docs/tasks/29-gh-signoff.md` を新設。
- `docs/tasks/00-overview.md` の表にトピック29 行を追加（ステータス: 進行中）。総トピック数を 24 → 25 に更新。
- `docs/tasks/PROGRESS_LOG.md` の表にトピック29 行を追加（進行中・Coder 担当）。

### 6. 動作確認

- 結果は本コミット作成時にマネージャーへ返却。
