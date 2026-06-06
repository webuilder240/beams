# トピック29: `gh signoff` でローカル CI を強制する

> [basecamp/gh-signoff](https://github.com/basecamp/gh-signoff) を導入し、`bin/ci` 完走時に commit status `signoff` を success で付与する。GitHub の Branch Protection（`signoff` 必須化）と組み合わせて「ローカル CI を回さずに PR をマージ」する抜け道を塞ぐ。

- **ステータス**: 進行中（2026-06-06 分解 → 同日実装）
- **依存**: 28（ローカル CI 化）
- **関連計画書**: 該当なし（運用品質向上）

---

## 背景

トピック28 で GitHub Actions の `pull_request` トリガを撤去し、PR 前のチェックを `bin/ci` でのローカル実行に切り替えた。コスト・待ち時間の削減には成功したものの、「ローカル CI を回さずに PR を作成 → そのままマージ」する抜け道が残った。これは Beams を複数人で開発する局面で品質ゲートを骨抜きにしうる。

[basecamp/gh-signoff](https://github.com/basecamp/gh-signoff) は手元のテスト完走時に GitHub の commit status を success に書き込む小さな `gh` extension。Beams 側で `bin/ci` 完走の直後にこれを呼び、Branch Protection で `signoff` status を必須化すれば、「テストを通した commit」しか main にマージできない強制力が生まれる。

---

## 変更内容

### 1. `bin/ci`（更新）

- 全ジョブ完走時の `==> all green` 出力直後にのみ `gh signoff` 呼び出しを追加する。**個別ジョブ実行（`bin/ci lint` 等）では呼ばない**。
- **オプトイン制御**: 環境変数 `BEAMS_CI_SIGNOFF=1` のときだけ実行する。デフォルトでは何もしない（gh / extension 未インストールの開発者でも `bin/ci` は壊れない安全側）。
- `BEAMS_CI_SIGNOFF=1` で `gh` または `gh-signoff` extension が見つからない場合は STDERR に明確なエラーを出して `exit 1`（`bin/ci` のジョブ自体は all green の後段で失敗扱いになる）。
- `set -e` 配下なので `gh signoff` 自体が失敗（認証切れ・ネットワーク不通など）したら exit code が伝播する。

### 2. `docs/INSTALL.md`（更新）

「## 11. 開発者向けセットアップ（オプション）」節を新設:

- `gh` CLI インストール先（`https://cli.github.com/`）への誘導
- `gh auth login` で認証
- `gh extension install basecamp/gh-signoff` 実行
- `BEAMS_CI_SIGNOFF=1` を shell rc に export
- リポジトリ管理者向け Branch Protection 設定手順（Settings → Branches → Add rule → `main` → Require status checks → `signoff` を選択）

### 3. `CLAUDE.md`（更新）

- `## Commands` の `bin/ci` ブロックに `BEAMS_CI_SIGNOFF=1 bin/ci` を 1 行追記。
- `## CI（GitHub Actions）` 節に `gh signoff` と Branch Protection の運用効果を 1〜2 行追記。

### 4. タスク文書

- `docs/tasks/29-gh-signoff.md`（本ファイル）。
- `docs/tasks/progress/29-gh-signoff.md` に時系列ログ。
- `docs/tasks/00-overview.md` と `docs/tasks/PROGRESS_LOG.md` の表にトピック29 行を追加。

---

## 受け入れ条件

- `bin/ci`（引数なし、`BEAMS_CI_SIGNOFF` 未設定）が all green まで完走し、signoff は実行されない（従来挙動を変えない）。
- `bin/ci lint` 等の個別ジョブで signoff が実行されない（個別ジョブは signoff の対象外）。
- `BEAMS_CI_SIGNOFF=1 bin/ci` で signoff まで進む。`gh` または `gh-signoff` extension が無い環境では STDERR に明確なエラーを出して `exit 1`。
- `docs/INSTALL.md` に開発者向けセットアップ手順と Branch Protection 手順が記載されている。
- `CLAUDE.md` の `## Commands` と `## CI（GitHub Actions）` に signoff の言及が入っている。
- `bin/rubocop` clean（Ruby コード変更なしのため変動なしの想定）。既存 RSpec を壊さない。

---

## 運用上の注意

- `BEAMS_CI_SIGNOFF` を未設定のまま `bin/ci` を回す開発者は、signoff status を付けない PR を作成しうる。Branch Protection で `signoff` 必須化していれば PR はマージできないので、CI ゲートとしては機能する（個人開発者の手元では `BEAMS_CI_SIGNOFF` 設定を推奨し、CLAUDE.md / INSTALL.md でその旨を案内する）。
- `gh signoff` は対象 commit に対して GitHub API 経由で status を打つため、push 済みでない最新 commit には付けられない（gh-signoff 側の仕様）。`bin/ci` 完走 → `git push` → 必要なら再度 `bin/ci`（または `gh signoff` を直接叩く）の順で運用する。
- 旧 commit に signoff が残ったまま amend / rebase で commit SHA が変わると status が再付与されないため、push 直前に CI を回す習慣を推奨する。

---

## 厳守

- `bin/ci` のデフォルト挙動は変えない（オプトイン）。既存ユーザーが何も設定せず `bin/ci` を回しても従来通り完走する。
- service クラス禁止は引き続き遵守（今回 Ruby コードの追加はない）。
- 偽の数値・ハッシュは書かない。
