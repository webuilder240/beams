# 進捗ログ — トピック18: KamalからONCE配信への移行

実装担当: Coder
ブランチ: `feat/18-once-distribution`
対象: **グループA「Kamal 撤去」のみ**（B以降は本タスク対象外）

## 2026-05-31

### やったこと（時系列）

1. `feat/18-once-distribution` ブランチを作成・チェックアウト。
2. Kamal 関連成果物を `git rm` で完全撤去:
   - `config/deploy.yml`
   - `bin/kamal`
   - `.kamal/`（`hooks/*.sample` 9ファイル + `secrets`）を `git rm -r`
3. `Gemfile` から以下を削除:
   - `# Deploy this application anywhere as a Docker container [https://kamal-deploy.org]`
   - `gem "kamal", require: false`
4. `bundle install` を実行し、`Gemfile.lock` から kamal とその依存を除去・再生成。
5. `Dockerfile` 冒頭コメント（4行目）の "Use with Kamal or build'n'run by hand:" を
   "Build and run by hand or via the ONCE installer (deploy/once/install.sh):" に書き換え。本文（CMD等）は不変。
6. `.dockerignore` の Kamal 無視設定 3行（`# Ignore Kamal files.` / `/config/deploy*.yml` / `/.kamal`）を削除。
7. `CLAUDE.md` のデプロイ節を ONCE 配布の記述に更新（`docs/INSTALL.md` 参照。※INSTALL.md はグループEで作成予定）。
8. `docs/PRODUCT_PLAN.md` 技術スタック表の「ONCE（Docker / Kamalベース）」を「ONCE（単一Dockerコンテナ）」に更新。
9. グループA のチェックボックスを `- [x]` に更新。

### 実行コマンドと実際の結果

- `bundle install`: 成功。`Bundle complete! 30 Gemfile dependencies, 153 gems now installed.`
  - `Gemfile.lock` から kamal 関連を削除（`git diff --stat Gemfile.lock` → 37 deletions）。
  - `grep -niE "kamal" Gemfile.lock` → 0件（NO kamal in Gemfile.lock）。

- `grep -rniE "kamal" . --exclude-dir=.git --exclude-dir=node_modules`:
  - 残存はすべて `docs/tasks/` 配下（タスク定義・マネージャーログ・移行履歴記述）→ **許容範囲**。
  - Gemfile / Gemfile.lock / config / bin / Dockerfile / .dockerignore / CLAUDE.md / docs/PRODUCT_PLAN.md には **kamal の残存なし**。

- `bin/rubocop`: `145 files inspected, no offenses detected`（exit 0）。

- `bin/rails db:test:prepare`: exit 0。

- `bundle exec rspec`: **509 examples, 0 failures**、Line Coverage **98.88% (975 / 986)**（exit 0）。基線（509 / 98.88%）と一致。

### 補足（環境メモ）

- 本 worktree には gitignore 対象の `config/master.key` が無く、初回 rspec が ActiveRecord 暗号化資格情報不足で失敗した。共有チェックアウトの `config/master.key` を worktree の `config/` にコピーして解消（gitignore のためコミット対象外）。
- system spec 用に `bin/rails tailwindcss:build` を事前実行（CI と同じ前提）。これらは Kamal 撤去とは無関係の環境セットアップ。

### グループA 完了の定義の充足

- 撤去対象ファイルがすべて消えている。
- Gemfile.lock に kamal が現れない。
- bundle install 成功・rspec green・カバレッジ85%以上維持。
- 既存テストを壊していない（509/509 green）。
