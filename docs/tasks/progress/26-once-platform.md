# 26-once-platform 実装進捗ログ

トピック: [docs/tasks/26-once-platform.md](../26-once-platform.md)
ブランチ: `feat/26-once-platform`（worktree 上では `worktree-agent-a132d21f9554fbe0e` 経由）

---

## 2026-06-06 グループ A: Thruster TLS 撤去・port 80 専用化

担当: Coder

### 進捗

- [x] `Beams::Once::TlsConfig` PORO（`lib/beams/once/tls_config.rb`）と `config/environments/production.rb` の `assume_ssl` / `force_ssl` / `ssl_options` 周辺（require と if ブロック）を撤去
- [x] `Dockerfile` の `EXPOSE 443` を削除し `EXPOSE 80` のみに変更。冒頭コメント（`deploy/once/install.sh` → `basecamp/once`）と末尾コメント（Thruster の TLS 終端言及）も整合修正
- [x] `spec/lib/beams/once/tls_config_spec.rb` を削除
- [x] `docs/INSTALL.md` から `TLS_DOMAIN` / `HTTPS_PORT` / `EXPOSE 443` / `Beams::Once::TlsConfig` 言及を撤去（F グループで本格刷新するための最小整合）
- [x] `CLAUDE.md` の TLS 関連記述に `TLS_DOMAIN` 言及はなし（grep 確認）

### TDD ログ

1. **Red**: `lib/beams/once/tls_config.rb` を削除した状態で `bundle exec rspec spec/lib/beams/once/tls_config_spec.rb` を実行。`LoadError: cannot load such file -- lib/beams/once/tls_config` が出て red 確認（`require_relative` 失敗）。
2. **Green**: `spec/lib/beams/once/tls_config_spec.rb` も削除し、`production.rb` から `require "beams/once/tls_config"` と `tls_config.enabled?` 分岐を撤去。これで TlsConfig 関連の全参照が消えて green。
3. **Refactor**: production.rb の SSL 強制ブロックの跡地に「グループ B で `DISABLE_SSL` env 判定に置き換える」コメントを残置。

### 検証

- `bundle exec rspec`: **540 examples, 0 failures**, Line Coverage **98.65% (1021 / 1035)**
  - 初回は `tailwind.css` 未ビルドで 135 system failures だったため `bin/rails tailwindcss:build` を実行してから再計測（CI も `tailwindcss:build` 後に実行する規約のため正常な手順）
- `bin/rubocop`: 155 files inspected, **no offenses detected**
- `grep -rnE 'TLS_DOMAIN|HTTPS_PORT|EXPOSE 443|TlsConfig'` を対象 4 ファイル（Dockerfile / production.rb / docs/INSTALL.md / CLAUDE.md）で実行 → ヒット 0
  - グループ B 以降で扱う `deploy/once/install.sh` / `lib/beams/once/updater.rb` / `docs/PRODUCT_PLAN.md` / `docs/tasks/18-once-distribution.md` / `docs/tasks/progress/18-once-distribution.md` / `docs/tasks/manager/18-once-distribution.md` には残置（指示通り触らない）

### 触らなかった範囲（指示の遵守）

- `bin/hooks/`、`lib/beams/once/pre_backup.rb`、`.github/workflows/release.yml`、`config/recurring.yml`、`bin/once-update`、`lib/beams/once/updater.rb`、`spec/lib/beams/once/updater_spec.rb`、`deploy/once/`、`docs/PRODUCT_PLAN.md` などはすべて未編集。

---

## 2026-06-06 グループ B: ONCE 環境変数規約への対応

担当: Coder
worktree: `/home/nick/tmp/beams/.claude/worktrees/agent-a2b29dea2b932cdd8`（feat/26-once-platform から派生）

### 進捗

- [x] `Beams::Once::SslMode` PORO を `lib/beams/once/ssl_mode.rb` に新設。`DISABLE_SSL=true` のときのみ `enabled? == false`、未設定/空文字/その他は `true`。`ssl_options` で `/up` を https リダイレクト対象から除外
- [x] `config/environments/production.rb` の跡地コメントを `SslMode` 利用の本実装に置換。`enabled?` が真のとき `assume_ssl` / `force_ssl` / `ssl_options` を設定
- [x] `RAILS_MASTER_KEY` 未設定でも boot 失敗しないことを `env -u RAILS_MASTER_KEY bundle exec rails runner 'p :ok'` および `RAILS_MASTER_KEY= bundle exec rails runner 'p :ok'` の 2 通りで確認（コード変更なし）
- [x] `docs/INSTALL.md` 末尾に「## ONCE 環境変数」節を追記。`RAILS_MASTER_KEY` の (a) CLI 経路 / (b) TUI 経路の 2 経路を記載し、`VAPID_*` / `SMTP_*` / `NUM_CPUS` を「現状無視で問題ない」と明記（F グループでの全面刷新を前提とした最小追記）

### TDD ログ

1. **Red**: `spec/lib/beams/once/ssl_mode_spec.rb` を先に作成し `bundle exec rspec spec/lib/beams/once/ssl_mode_spec.rb` を実行 → `LoadError: cannot load such file -- .../lib/beams/once/ssl_mode`（require_relative 失敗）で red 確認
2. **Green**: `lib/beams/once/ssl_mode.rb` を実装（`env:` キーワード引数、`enabled?`、`ssl_options`）→ 8 examples / 0 failures で green
3. **Refactor**: `production.rb` の require を追加し、跡地コメントを `SslMode` 利用の if ブロックに置換。`/up` 除外プロックは PORO 側に集約しているので production.rb 側は薄い

### 検証

- `bin/rails db:test:prepare` → ok
- `bin/rails tailwindcss:build` → Done in 63ms（system spec 前提）
- `bundle exec rspec`: **548 examples, 0 failures**, Line Coverage **98.66% (1030 / 1044)**
- `bin/rubocop`: **157 files inspected, no offenses detected**
- `env -u RAILS_MASTER_KEY bundle exec rails runner 'p :ok'` → `:ok`
- `RAILS_MASTER_KEY= bundle exec rails runner 'p :ok'` → `:ok`

### 編集/作成ファイル

- 新規: `lib/beams/once/ssl_mode.rb`
- 新規: `spec/lib/beams/once/ssl_mode_spec.rb`
- 編集: `config/environments/production.rb`（require + SslMode 利用ブロック）
- 編集: `docs/INSTALL.md`（末尾に「## ONCE 環境変数」節を追加）
- 編集: `docs/tasks/26-once-platform.md`（グループ B チェックボックスを `[x]` に）
- 編集: `docs/tasks/progress/26-once-platform.md`（本セクション追加）

### 触らなかった範囲

- C グループ以降のファイル（`bin/hooks/`、`lib/beams/once/pre_backup.rb`、`.github/workflows/release.yml`、`config/recurring.yml`、`bin/once-update`、`lib/beams/once/updater.rb`、`spec/lib/beams/once/updater_spec.rb`、`deploy/once/*`）はいずれも未編集
- A グループで撤去済みの `lib/beams/once/tls_config.rb` は復活させていない

---

## 2026-06-06 グループ C: `/hooks/pre-backup` 実装

担当: Coder
worktree: `/home/nick/tmp/beams/.claude/worktrees/agent-a73730d2807138585`（feat/26-once-platform から派生、HEAD c9b25f6 で同期）

### 進捗

- [x] `lib/beams/once/pre_backup.rb` を新規追加（PORO `Beams::Once::PreBackup`）。`Beams::Backup.default_sources` を流用して 4 DB（production / cache / queue / cable）を `VACUUM INTO` で `destination` に安全コピー。`PRAGMA integrity_check` を必ず実行し `ok` 以外なら raise。出力先は `ONCE_PRE_BACKUP_DIR` env で上書き可（既定 `/storage/backups/once-pending`）
- [x] `bin/hooks/pre-backup` を新規追加（Ruby 薄ラッパー・mode 0755）。Rails を boot させず `$LOAD_PATH` に `lib/` を追加してから PORO を直接 require → 実行。成功時は各 DB の整合性結果を STDOUT に出して `exit 0`、失敗時は STDERR にバックトレースを出して `exit 1`
- [x] `Dockerfile` 最終ステージで `cp /rails/bin/hooks/pre-backup /hooks/pre-backup` + `chmod 755` を追加（USER root に一時切替して所有者を rails に設定し、すぐ非 root に戻す）
- [x] `/hooks/post-restore` は**不要と判断**。理由: `once-pending/` ディレクトリは ONCE 側で取得・破棄するため掃除不要、4 つの Solid* DB はリストア後の Rails 起動時に自動的に migration/復帰し追加処理を要しない。`bin/hooks/post-restore` は作成しない
- [x] `config/recurring.yml` から `daily_backup:`（class: BackupJob）ブロックを撤去。残置コメントで「自動バックアップは ONCE の hook に一本化、緊急時用に `rake beams:backup` を維持」を明記。`clear_solid_queue_finished_jobs:` は維持
- [x] `spec/config/recurring_spec.rb` を「BackupJob エントリが**ない**ことを検証」する内容に書き換え（同 file に YAML パース正常性チェックも追加）
- [x] `BackupJob` クラス本体（`app/jobs/backup_job.rb`）と `spec/jobs/backup_job_spec.rb` / `spec/integration/backup_job_integration_spec.rb` は手動緊急時用として温存（指示通り）
- [x] `docs/INSTALL.md` に「## バックアップ（ONCE 統合）」節を追加（最小限の方針追記。グループ F で本格刷新）
- [x] `docs/RESTORE.md` 冒頭に「トピック 26 以降の方針」blockquote を追加（自動バックアップは ONCE TUI、`rake beams:backup` は手動緊急時用）

### TDD ログ

1. **Red (PORO)**: 先に `spec/lib/beams/once/pre_backup_spec.rb` を 7 例書く → `bundle exec rspec` で `LoadError: cannot load such file -- beams/once/pre_backup`（red 確認）
2. **Green (PORO)**: `lib/beams/once/pre_backup.rb` を実装 → 7 examples, 0 failures
3. **Red (bin)**: `spec/bin/hooks/pre_backup_spec.rb` を 5 例書く（exists / mode 0755 / shebang / `Beams::Once::PreBackup.new.run` 文字列 / Rails 非依存）→ 5 例とも No such file or directory で red 確認
4. **Green (bin)**: `bin/hooks/pre-backup` を実装し `chmod 755` → 5 examples, 0 failures
5. **Refactor**: 出力フォーマット（成功時 STDOUT 1 行/DB）を整理。整合性チェック失敗時の例外パスを spec で network から独立した stub で検証（`allow(pre_backup).to receive(:integrity_check).and_return("malformed")`）

### 検証

- `bin/rails db:test:prepare` → ok
- `bin/rails tailwindcss:build` → Done in 73ms（system spec 前提、CI 規約通り）
- `bundle exec rspec spec/lib/beams/once/pre_backup_spec.rb spec/bin/hooks/pre_backup_spec.rb` → **12 examples, 0 failures**
- `bundle exec rspec`（全件・以下「最終検証」に実測値）
- 手動スモーク: `ONCE_PRE_BACKUP_DIR=/tmp/dest bin/hooks/pre-backup` を一時 `storage/production.sqlite3` シードに対して実行 → `/tmp/dest/production.sqlite3` 8192 bytes, integrity=ok を確認


### 最終検証（全件実行）

- `bin/rails db:test:prepare` → ok
- `bin/rails tailwindcss:build` → Done in 57ms
- `bundle exec rspec`: **560 examples, 0 failures**, Line Coverage **98.7% (1062 / 1076)**（カバレッジ 85% 閾値クリア）
- `bin/rubocop`: **161 files inspected, no offenses detected**
- `ls -l bin/hooks/pre-backup` → `-rwxr-xr-x 1 nick nick 856 Jun  6 18:01 bin/hooks/pre-backup`（mode 0755）

### 編集/作成ファイル

- 新規: `lib/beams/once/pre_backup.rb`（PORO 本体）
- 新規: `spec/lib/beams/once/pre_backup_spec.rb`（PORO の TDD spec、7 例）
- 新規: `bin/hooks/pre-backup`（mode 0755、薄ラッパー）
- 新規: `spec/bin/hooks/pre_backup_spec.rb`（bin スクリプト内容検査、5 例）
- 編集: `Dockerfile`（最終ステージで `/hooks/pre-backup` をコピー＋実行権限付与）
- 編集: `config/recurring.yml`（`daily_backup` ブロック撤去、コメントで方針明記）
- 編集: `spec/config/recurring_spec.rb`（BackupJob 不在を検証する内容に書き換え）
- 編集: `docs/INSTALL.md`（「## バックアップ（ONCE 統合）」節を追加）
- 編集: `docs/RESTORE.md`（冒頭にトピック 26 以降の方針 blockquote 追加）
- 編集: `docs/tasks/26-once-platform.md`（グループ C 全 6 項目を `[x]`、post-restore 判断結果を本文に追記）
- 編集: `docs/tasks/progress/26-once-platform.md`（本セクション追加）

### 触らなかった範囲

- A グループ完了済みファイル（`lib/beams/once/tls_config.rb` 等）はそのまま
- B グループ完了済みファイル（`lib/beams/once/ssl_mode.rb`、`config/environments/production.rb` 等）はそのまま
- D グループ対象（`deploy/once/*`、`bin/once-update`、`lib/beams/once/updater.rb`、`spec/lib/beams/once/updater_spec.rb`、`docs/tasks/18-once-distribution.md`）は未編集
- E グループ対象（`.github/workflows/release.yml`、`README.md`）は未編集
- F グループ対象（`docs/INSTALL.md` の本格刷新、`docs/PRODUCT_PLAN.md`、`CLAUDE.md` デプロイ節）は未編集（本グループでは方針追記のみ）
- `lib/beams/backup.rb` / `rake beams:backup` / `bin/beams-backup` / `bin/beams-restore` / `app/jobs/backup_job.rb` / `spec/jobs/backup_job_spec.rb` / `spec/integration/backup_job_integration_spec.rb` は手動緊急時用として温存

---

## 2026-06-06 グループ D: 旧自前配布層（`deploy/once/*`）撤去

担当: Coder
worktree: `/home/nick/tmp/beams/.claude/worktrees/agent-ab41525bdabf07875`（feat/26-once-platform から派生）

### 進捗

- [x] `deploy/once/install.sh` を削除（`git rm`）
- [x] `deploy/once/once-update.service` / `deploy/once/once-update.timer` を削除（`git rm`）。`deploy/once/` が空になり、`deploy/` 直下も空になったため、Git 上ではディレクトリ自体も自動的に消滅
- [x] `bin/once-update` を削除（`git rm`）
- [x] `lib/beams/once/updater.rb` および `spec/lib/beams/once/updater_spec.rb` を削除（`git rm`）。`updater_spec.rb` は単体で完結しており、他 spec への波及なし
- [x] `docs/tasks/18-once-distribution.md` 冒頭に「トピック 26 で全撤去」の相互参照 blockquote を追加（履歴のため個別チェックボックスは据え置き）
- [x] `docs/INSTALL.md` から `deploy/once/install.sh` / `bin/once-update` / `once-update.service` / `once-update.timer` / `lib/beams/once/updater.rb` への言及をすべて削除し、「グループ F で全面刷新する」旨の暫定注記に置換
- [x] `docs/PRODUCT_PLAN.md` §2 配布形態の段落から旧ファイル参照を撤去し、`basecamp/once` 統合済みである旨に書き換え
- [x] `grep -rE 'deploy/once|once-update|TlsConfig|Beams::Once::Updater'`（`.git` / `.claude` / `node_modules` / `coverage` / `docs/tasks/` 除外）の結果が **0 件**

### 検証

- `git rm` 出力（6 ファイル）:
  - `bin/once-update`
  - `deploy/once/install.sh`
  - `deploy/once/once-update.service`
  - `deploy/once/once-update.timer`
  - `lib/beams/once/updater.rb`
  - `spec/lib/beams/once/updater_spec.rb`
- `grep -rE 'deploy/once|once-update|TlsConfig|Beams::Once::Updater' --exclude-dir='.git' --exclude-dir='.claude' --exclude-dir='node_modules' --exclude-dir='coverage' . | grep -v 'docs/tasks/'` → **0 行**（exit 1）
- `bin/rails db:test:prepare` → ok
- `bin/rails tailwindcss:build` → Done in 48ms
- `bundle exec rspec`: **554 examples, 0 failures**, Line Coverage **98.93% (1017 / 1028)**（85% 閾値クリア）
  - 内訳: non-system 474 examples / system 80 examples いずれも 0 failures（初回は `tailwindcss:build` 未実行で system 側が落ちたが、ビルド後に再実行して green）
- `bin/rubocop`: **159 files inspected, no offenses detected**

### 編集/削除ファイル

- 削除（`git rm`）: `deploy/once/install.sh`, `deploy/once/once-update.service`, `deploy/once/once-update.timer`, `bin/once-update`, `lib/beams/once/updater.rb`, `spec/lib/beams/once/updater_spec.rb`
- 編集: `docs/INSTALL.md`（冒頭注記ボックス・§2 インストール手順・§4 ポート・§7 自動アップデート・§8 手動アップデート/ロールバックから旧ファイル言及を撤去）
- 編集: `docs/PRODUCT_PLAN.md`（§2 配布形態の段落を旧ファイル参照なしの記述に置換）
- 編集: `docs/tasks/18-once-distribution.md`（冒頭に 26 への相互参照 blockquote を追加）
- 編集: `docs/tasks/26-once-platform.md`（グループ D 全 6 項目を `[x]`）
- 編集: `docs/tasks/progress/26-once-platform.md`（本セクション追加）

### 触らなかった範囲

- A/B/C グループ完了済みファイルはそのまま
- E グループ対象（`.github/workflows/release.yml`、`README.md` のプル元 URL 記載）は未編集
- F グループ対象（`docs/INSTALL.md` の本格刷新、`CLAUDE.md` デプロイ節）は最小編集のみ（D の grep 0 件要件のため `docs/INSTALL.md` からの旧言及削除は本グループで実施。F での全面刷新と衝突しない）
- `lib/beams/backup.rb` / `rake beams:backup` / `bin/beams-backup` / `bin/beams-restore` などの手動バックアップ系は維持

---

## 2026-06-06 グループ E: ghcr.io への公開 CI

担当: Coder
worktree: `/home/nick/tmp/beams/.claude/worktrees/agent-a2a465ac98e5e93ce`（feat/26-once-platform から派生、HEAD fd56087 で同期）

### 進捗

- [x] `.github/workflows/release.yml` を新規追加。トリガは `push` to `main` および `workflow_dispatch`。`docker/setup-qemu-action@v3` + `docker/setup-buildx-action@v3` + `docker/login-action@v3` + `docker/build-push-action@v6` で `linux/amd64,linux/arm64` の multi-arch ビルド・push を実装
- [x] イメージ名は `ghcr.io/webuilder240/beams`、タグは `:latest` および `:${{ github.sha }}` の 2 つ
- [x] `permissions:` ブロックで `contents: read` / `packages: write` を付与。レジストリログインは `${{ github.actor }}` + `${{ secrets.GITHUB_TOKEN }}`（追加 secrets 不要）
- [x] OCI labels（`org.opencontainers.image.source` / `description` / `revision`）を付与。`licenses` は LICENSE ファイルが存在しないため含めず（指示通り）
- [x] GitHub Actions cache（`cache-from: type=gha` / `cache-to: type=gha,mode=max`）を有効化
- [x] `concurrency:` で `release-${{ github.ref }}` グループ・`cancel-in-progress: true` を設定し、main への連続 push が重なった場合は古い方をキャンセル
- [x] `README.md` 冒頭に「配布イメージ」節を追加し `ghcr.io/webuilder240/beams:latest` を明記
- [x] `docs/INSTALL.md` の `IMAGE` プレースホルダ（`ghcr.io/REPLACE_ME/beams:latest`）を実 URL に置換（注意ブロックと環境変数表の 2 箇所）。F グループでの全面刷新と衝突しない最小編集

### 検証

- `ruby -ryaml -e 'p YAML.load_file(".github/workflows/release.yml").keys'` → `["name", true, "concurrency", "permissions", "jobs"]`（YAML パース成功。`true` キーは Ruby の YAML 1.1 で `on:` が真偽値として解釈されるため正常）
- `actionlint` は未インストール（`which actionlint` → 出力なし）のためスキップ
- `bin/rails db:test:prepare` → ok
- `bin/rails tailwindcss:build` → 実行済み
- `bundle exec rspec` → 後述「最終検証」参照
- `bin/rubocop` → 後述「最終検証」参照

### 編集/作成ファイル

- 新規: `.github/workflows/release.yml`
- 編集: `README.md`（冒頭に「配布イメージ」節を追加）
- 編集: `docs/INSTALL.md`（`IMAGE` プレースホルダ 2 箇所を `ghcr.io/webuilder240/beams:latest` に置換）
- 編集: `docs/tasks/26-once-platform.md`（グループ E 全 4 項目を `[x]`）
- 編集: `docs/tasks/progress/26-once-platform.md`（本セクション追加）

### 触らなかった範囲

- F グループ対象（`docs/INSTALL.md` の全面刷新・`CLAUDE.md` デプロイ節・`docs/PRODUCT_PLAN.md`）は触らず。`IMAGE` プレースホルダの実 URL 置換のみ「E の要件」として実施
- 既存 `.github/workflows/ci.yml` は触らず（並列で動作する）
- 既存テスト・既存実装はいずれも未編集

---

## 2026-06-06 グループ F: `docs/INSTALL.md` を ONCE 手順に刷新

担当: Coder
worktree: `/home/nick/tmp/beams/.claude/worktrees/agent-ad1d3f17aedb26ca4`（feat/26-once-platform から派生、HEAD 4cbfb4a で同期）

### 進捗

- [x] `docs/INSTALL.md` を全面刷新。旧暫定注記（§2 / §7 / §8 の "トピック 26 グループ F で刷新予定" blockquote、独立節「ONCE 環境変数」「バックアップ（ONCE 統合）」）を撤去し、章立てを 1〜10 の連番に再構成
  - § 1 前提（OS / Docker / DNS A レコード）
  - § 2 インストール（ONCE CLI 導入 → TUI 経路 / CLI 一発経路）
  - § 3 初期 env（`RAILS_MASTER_KEY` を ONCE custom env で渡す 2 経路）
  - § 4 バックアップ（自動: ONCE TUI Backups → `/hooks/pre-backup`。手動: `rake beams:backup` を緊急時用に維持）
  - § 5 アップデート（ONCE 内蔵の自動アップデート / TUI action menu）
  - § 6 ロールバック（ONCE TUI でイメージタグ固定 / バックアップ世代復旧）
  - § 7 ポート（HTTP 80 のみ・TLS は ONCE が自動終端）
  - § 8 環境変数（Beams 利用 env と ONCE 由来の未使用 env を統合）
  - § 9 ヘルスチェック
  - § 10 関連ドキュメント
  - 旧 install.sh / once-update / systemd timer / Thruster TLS 終端の言及は一切残さない
- [x] `CLAUDE.md` のデプロイ節を「ONCE プラットフォーム（basecamp/once）で配布する。設置手順は `docs/INSTALL.md` を参照。」に置換
- [x] `docs/PRODUCT_PLAN.md` §2 配布形態の段落で「自前 `install.sh` は撤去」を明示。§2.2 の Thruster 記述から SSL 終端を削除（TLS は ONCE 担当）。技術スタック表の Webサーバ行も SSL 記述を削除し「TLS 終端は ONCE 担当」に置換
- [x] `docs/tasks/18-once-distribution.md` の「ステータス: 未着手」を「ステータス: ✅完了（履歴・トピック26 で全撤去）」に修正（実体との整合）
- [x] `README.md` から Rails 標準の plant text "Things you may want to cover: ..." セクションを削除。配布イメージ・インストール手順（`docs/INSTALL.md`）・主要 env をまとめた簡潔な README に整える。Bugsnag 表の `.kamal/secrets` 記述を「ONCE の custom env または `--env KEY=VALUE` で渡す」に修正

### 検証

- `bin/rails db:test:prepare` → ok
- `bin/rails tailwindcss:build` → 実行
- `bundle exec rspec` → 後述「検証実測」
- `bin/rubocop` → 後述「検証実測」

### 編集ファイル

- 編集: `docs/INSTALL.md`（全面刷新）
- 編集: `CLAUDE.md`（デプロイ節）
- 編集: `docs/PRODUCT_PLAN.md`（§2 配布形態・§2.2 Thruster 記述・§3 技術スタック表 Webサーバ行）
- 編集: `docs/tasks/18-once-distribution.md`（ステータス行修正）
- 編集: `README.md`（Rails plant text 削除・インストール節追加・環境変数表更新）
- 編集: `docs/tasks/26-once-platform.md`（グループ F 全 4 項目を `[x]`）
- 編集: `docs/tasks/progress/26-once-platform.md`（本セクション追加）

### 触らなかった範囲

- A〜E グループ完了済みファイル（コード・spec・`Dockerfile`・`config/recurring.yml`・`.github/workflows/release.yml`・`config/environments/production.rb`・`lib/beams/once/*`・`bin/hooks/pre-backup` 等）はすべて未編集
- F は純粋な docs 編集のため、ロジック・テストには一切触っていない

---

## 2026-06-06 Reviewer リファクタ対応

担当: Coder
worktree: `/home/nick/tmp/beams/.claude/worktrees/agent-a567efd66d573fa89`（feat/26-once-platform HEAD 72c3913 から派生）

### 対応した指摘

#### must

- [x] **M1**: `docs/RESTORE.md` の「自動実行は SolidQueue の定期実行（`config/recurring.yml` の `daily_backup`）で行う。外部 cron 不要。worker プロセス稼働が前提。」を、冒頭 blockquote と整合する「自動バックアップは ONCE プラットフォーム側（`/hooks/pre-backup` 経由）で取得・世代管理される。`config/recurring.yml` の `daily_backup` は撤去済み。」に書き換え
- [x] **M2**: `bin/hooks/pre-backup` の冒頭で `Dir.chdir(File.expand_path("../..", __dir__))` を実行し、`Beams::Backup.default_sources` が `Dir.pwd` 起点で `/rails/storage/*.sqlite3` を返すよう保証。`spec/bin/hooks/pre_backup_spec.rb` に「`Dir.chdir(File.expand_path("../..", __dir__))` の痕跡を確認する」1 ケース追加

#### should

- [x] **S1**: `Dockerfile` の `/hooks/pre-backup` 配置を `RUN mkdir + cp + chmod + chown`（USER root↔1000 切替あり）から `COPY --chmod=0755 --chown=rails:rails bin/hooks/pre-backup /hooks/pre-backup` 一行に置換。ビルダーステージから直接配置するため USER 切替が不要に
- [x] **S6**: `Beams::Backup.snapshot(source_path:, dest_path:)` クラスメソッドを `lib/beams/backup.rb` に追加（`VACUUM INTO` + `PRAGMA integrity_check`、返り値は integrity 結果）。`Beams::Backup#snapshot` プライベートメソッドも内部でこのクラスメソッドを利用するよう書き換え。`Beams::Once::PreBackup` から `online_backup` / `integrity_check` プライベートメソッドを撤去し、`Beams::Backup.snapshot` を呼ぶ実装に整理。`require "sqlite3"` も `Beams::Backup` 経由に集約
- [x] **S7**: `bin/hooks/pre-backup` 冒頭に `require "bundler/setup"` を追加（`$LOAD_PATH` 操作の直前）。Rails boot は依然として行わない。`spec/bin/hooks/pre_backup_spec.rb` に `require "bundler/setup"` を含むことをアサートする 1 ケース追加
- [x] **S3 (簡易対応)**: `.github/workflows/release.yml` の OCI labels に `org.opencontainers.image.title=Beams` と `org.opencontainers.image.created=${{ github.event.head_commit.timestamp }}` を追加。`docker/metadata-action` は導入せず手書きで 2 行追加のみ
- [x] **S4**: `.github/workflows/release.yml` の `concurrency.cancel-in-progress` を `true` → `false` に変更。publish 中の race を防ぐ意図のコメントも添えた

#### nice-to-have

- [x] **N1**: `Beams::Once::SslMode#ssl_options` の戻り値を `SSL_OPTIONS` 定数（`.freeze`）に切り出し、インスタンスメソッドは定数を返すだけ。`production.rb` 側はインスタンスメソッド呼び出しを維持しているため互換性影響なし。`DISABLE_SSL` 比較行にも「ONCE 規約に厳密準拠」のコメントを 1 行追記
- [x] **N6**: `docs/PRODUCT_PLAN.md` §2.2 の Thruster 説明から「HTTP/2」を「HTTP（h2c も可）」に書き換え

### 対応しなかった指摘（参考記録）

- **S2 (git-sha 短縮タグ追加)**: タスクファイルが 2 タグ運用（`:latest` / `:<git-sha>`）を明示しているためマネージャー判断で見送り
- **S5 (private stub の脆さ)**: 動作上問題なし、設計判断で現状維持
- **S8 (hook spec の grep 脆性)**: 動作上問題なし、現状維持
- **N2 (DISABLE_SSL の寛容化)**: ONCE 規約厳密準拠。コードは現状維持し、コメントだけ N1 内で追加
- **N3 (checkout fetch-depth)**: 必要性低、見送り
- **N4 (provenance/SBOM)**: 将来課題、見送り
- **N5 (HTTP_PORT 説明補足)**: 既存表で機能、見送り
- **N7 (Red/Green コミット分離)**: 運用方針議論で対応不要

### TDD ログ

1. **Red**: `spec/lib/beams/backup_spec.rb` に `.snapshot` の describe ブロックを追加（クラスメソッド未実装の状態） → `NoMethodError: undefined method 'snapshot' for class Beams::Backup` で red 確認
   - 同時に `spec/bin/hooks/pre_backup_spec.rb` に `Dir.chdir(...)` 痕跡と `require "bundler/setup"` を期待する 2 ケース追加 → expected match を満たさず red 確認
2. **Green**:
   - `lib/beams/backup.rb` に `Beams::Backup.snapshot(source_path:, dest_path:)` を実装し、内部の `#snapshot` プライベートメソッドもこの新 API を経由するよう書き換え（既存 `online_backup` / `integrity_check` プライベートは新 API に吸収）
   - `lib/beams/once/pre_backup.rb` を簡素化し、`Beams::Backup.snapshot` を呼ぶ実装に
   - `bin/hooks/pre-backup` に `Dir.chdir(...)` と `require "bundler/setup"` を追加
   - `spec/lib/beams/once/pre_backup_spec.rb` の `integrity_check` private stub を `allow(Beams::Backup).to receive(:snapshot).and_return("malformed")` に書き換え（メソッドが移動したため。期待挙動は不変）
3. **Refactor**: SslMode の `SSL_OPTIONS` 定数切り出し（N1）、Dockerfile の COPY 一行化（S1）、release.yml の OCI labels 追加（S3）と `cancel-in-progress: false`（S4）、docs（M1 / N6）を実施

### 検証（実測）

- `bin/rails db:test:prepare` → ok
- `bin/rails tailwindcss:build` → Done in 56ms
- `bundle exec rspec` → **559 examples, 0 failures**, Line Coverage **98.92% (1005 / 1016)**
- `bin/rubocop` → 159 files inspected, **no offenses detected**

### 編集／作成ファイル

- 編集: `docs/RESTORE.md`（M1）
- 編集: `bin/hooks/pre-backup`（M2 / S7）
- 編集: `Dockerfile`（S1: RUN ブロック → COPY 一行）
- 編集: `lib/beams/backup.rb`（S6: `.snapshot` クラスメソッド追加 + `#snapshot` privatre 経由化）
- 編集: `lib/beams/once/pre_backup.rb`（S6: 自前 `online_backup` / `integrity_check` 撤去）
- 編集: `lib/beams/once/ssl_mode.rb`（N1: `SSL_OPTIONS` 定数 + コメント）
- 編集: `.github/workflows/release.yml`（S3 / S4）
- 編集: `docs/PRODUCT_PLAN.md`（N6: Thruster 説明）
- 編集: `spec/bin/hooks/pre_backup_spec.rb`（M2 / S7 のアサート 2 件追加）
- 編集: `spec/lib/beams/backup_spec.rb`（S6: `.snapshot` describe ブロック 3 ケース追加）
- 編集: `spec/lib/beams/once/pre_backup_spec.rb`（S6: integrity stub を `Beams::Backup.snapshot` に切替）
- 編集: `docs/tasks/progress/26-once-platform.md`（本セクション追加）

### 触らなかった範囲

- `docs/tasks/26-once-platform.md` のチェックボックスは指示通り変更なし（全項目すでに `[x]`）
- A〜F 完了済み機能の振る舞いは不変（既存テスト 559 examples すべて green）

