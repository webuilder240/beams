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

---

## 2026-05-31 — グループB「TLS 自動証明（Thruster）」

対象: グループB のうち `Dockerfile`（EXPOSE 443）と `production.rb`（TLS_DOMAIN 条件付き SSL 強制）。
3 つ目の「Thruster env を docs/INSTALL.md に整理」は INSTALL.md（グループE）依存のため本タスク対象外（未チェックのまま）。

### 選んだ TLS 検証方式と理由

- TLS 有効判定ロジックを **PORO `Beams::Once::TlsConfig`（`lib/beams/once/tls_config.rb`）** に切り出し、`spec/lib/beams/once/tls_config_spec.rb` で単体検証した。
- 理由:
  - production 環境設定を test からブートして検証するのは脆く、CI 環境差にも弱い。判定ロジックを小さな PORO に閉じ込め、ENV を `env:` キーワードで注入可能にすれば、ENV あり/なし・`/up` 除外ラムダの双方を高速・確定的に検証できる。
  - service クラス禁止の制約に抵触しないよう、既存 `lib/beams/`（backup/restore/procfile_reader）と同じ「`lib/` 配下の PORO + `spec/lib/`」の置き場所・規約に揃えた（`spec_helper` + `require_relative`）。
  - `production.rb` 側には分岐ロジックを直書きせず、PORO の `enabled?` / `ssl_options` を呼ぶだけにした。

### TDD（Red→Green）

1. 先に `spec/lib/beams/once/tls_config_spec.rb` を作成。
   - Red: `bundle exec rspec spec/lib/beams/once/tls_config_spec.rb`
     → `LoadError: cannot load such file -- .../lib/beams/once/tls_config`（PORO 未作成のため。0 examples / 1 error）。
2. `lib/beams/once/tls_config.rb` を実装。
   - Green: 同 spec → **6 examples, 0 failures**。

### 実装内容

- `lib/beams/once/tls_config.rb`: `enabled?`（`TLS_DOMAIN` が空でなければ true）/ `ssl_options`（`/up` を https リダイレクト除外するラムダ）を返す PORO。ENV は `env: ENV` で注入可能。
- `config/environments/production.rb`:
  - 冒頭で `require "beams/once/tls_config"`（環境設定評価時点では Zeitwerk オートロード未整備のため明示 require。`lib/beams/backup.rb` 等と同方針）。
  - `Beams::Once::TlsConfig.new.enabled?` が true のときだけ `config.assume_ssl = true` / `config.force_ssl = true` / `config.ssl_options = ...ssl_options` を設定。既存のコメントアウト行を活かした。
- `Dockerfile`: `EXPOSE 80` に加え `EXPOSE 443` を追加（コメントで Thruster の 80/443 挙動を明示）。

### 実コマンドと結果

- production 実ブート確認（参考。コミット対象外の手動確認）:
  - `TLS_DOMAIN` 未設定: `assume_ssl=false` / `force_ssl=false`（従来どおり）。
  - `TLS_DOMAIN=beams.example.com`: `assume_ssl=true` / `force_ssl=true`、`ssl_options` の exclude ラムダが `/up`→true・`/queries`→false。
- `bin/rubocop`: `147 files inspected, no offenses detected`（exit 0）。
- `bin/rails db:test:prepare` → exit 0。
- `bundle exec rspec`: **515 examples, 0 failures**、Line Coverage **98.9% (985 / 996)**（exit 0）。基線 509 から新規 PORO spec の 6 examples 増。

### 迷った点

- `production.rb` で PORO を autoload に任せられるか試したところ、環境設定評価時点では Zeitwerk が未整備で `uninitialized constant Beams::Once (NameError)` となった。既存 `lib/beams/*` と同じく明示 `require` で解決（dev/test の挙動には影響しない。production.rb は production 環境でのみ評価される）。
