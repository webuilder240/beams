# トピック26: ONCE プラットフォームへの移行（basecamp/once 採用）

- **ステータス**: 未着手
- **依存**: [[18-once-distribution]]（撤去対象）、[[02-once-deployment]]（`bin/boot` / `/storage` / `/up` は活用）
- **分解日**: 2026-06-06

---

## 背景・ゴール

[basecamp/once](https://github.com/basecamp/once) は Docker ベース web アプリの自己ホスト運用を簡略化する Go 製 CLI/TUI プラットフォーム（`curl https://get.once.com | sh` で配布）。
インストール・自動アップデート・バックアップ・TLS 自動化・ダッシュボードを内蔵する。

Beams は ONCE 互換要件（port 80・`/up`・`/storage`）をほぼ満たしているため、[[18-once-distribution]] で自前実装した配布層（`deploy/once/install.sh` / `bin/once-update` / `lib/beams/once/updater.rb` / Thruster TLS 終端 / systemd unit）を全廃し、**basecamp/once を採用する**。

### 完了の定義

- `once` CLI で `ghcr.io/webuilder240/beams:<tag>` を install → セットアップウィザード到達 → BigQuery 接続テスト成功までが TUI 完結
- ONCE TUI で `RAILS_MASTER_KEY` を custom env として渡し、Active Record Encryption が機能する
- `/hooks/pre-backup` 経由で ONCE バックアップが整合性ありで動作（4 つの SQLite すべて）
- 旧 `deploy/once/*` / `bin/once-update` / `lib/beams/once/{updater,tls_config}.rb` および関連 spec が削除されている
- `bundle exec rspec` green / カバレッジ 85%+ / `bin/rubocop` clean

---

## ONCE 互換アプリ要件（参考）

basecamp/once README より:

1. Docker コンテナとして配布
2. HTTP を **ポート 80** で提供
3. **`/up`** ヘルスチェックが 200 を返す
4. 永続データを **`/storage`**（Rails 互換のため `/rails/storage` も同じ volume にマウントされる）
5. 任意フック: `/hooks/pre-backup`（バックアップ前の安全コピー生成）、`/hooks/post-restore`（リストア後の整合性回復）
6. ONCE が渡す env: `SECRET_KEY_BASE`（インストール時生成・以後保持）、`DISABLE_SSL`（SSL 無効時 true）、`VAPID_*` / `SMTP_*` / `NUM_CPUS` 等

---

## グループ A. Thruster TLS 撤去・port 80 専用化

- [x] `Beams::Once::TlsConfig` PORO とその参照（`config/environments/production.rb` の `assume_ssl` / `force_ssl` 周辺）を撤去する (`lib/beams/once/tls_config.rb`, `config/environments/production.rb`)
  - 受け入れ条件: TDD。先に spec から `TlsConfig` 参照を外した状態で red を確認 → コード削除で green に
- [x] `Dockerfile` の `EXPOSE 443` を削除し `EXPOSE 80` のみに変更。Thruster の HTTPS 関連 env 既定値（`HTTPS_PORT` 等）も撤去 (`Dockerfile`)
  - 受け入れ条件: `docker build` 成功、`docker inspect` で expose ポートが 80 のみ
- [x] `spec/lib/beams/once/tls_config_spec.rb` を削除（または `DISABLE_SSL` 反転判定の spec に置換、配置先は B グループで決定） (`spec/lib/beams/once/tls_config_spec.rb`)
  - 受け入れ条件: `rspec` green、カバレッジ 85%+ 維持
- [x] `docs/INSTALL.md` / `CLAUDE.md` の TLS 関連記述から `TLS_DOMAIN` を撤去（F グループで本格的に書き直すが、A 完了時点で矛盾しないよう最低限の整合を取る） (`docs/INSTALL.md`, `CLAUDE.md`)

## グループ B. ONCE 環境変数規約への対応

- [ ] `DISABLE_SSL` が `true` 以外のときに `assume_ssl` / `force_ssl` を有効化する判定を `production.rb` または新 PORO（`lib/beams/once/ssl_mode.rb` 等）で実装する。`/up` は SSL リダイレクトから除外 (`config/environments/production.rb`, `lib/beams/once/`)
  - 受け入れ条件: TDD。spec で `DISABLE_SSL=true` / 未設定 / 空文字 の 3 ケースを検証。サービスクラス禁止のため PORO で実装
- [ ] `SECRET_KEY_BASE` は Rails 標準で `Rails.application.secret_key_base` が拾うので追加コードなし。ただし `RAILS_MASTER_KEY` を必須から「Active Record Encryption / credentials を使うときのみ必要」に格下げする方針を `config/application.rb` 周辺で検証（boot 失敗しないことを確認） (`config/application.rb`, `config/environments/production.rb`)
  - 受け入れ条件: `RAILS_MASTER_KEY` 未設定の状態で `bundle exec rails runner 'p :ok'` が通る（credentials を参照しない範囲で）
- [ ] `RAILS_MASTER_KEY` を ONCE の custom env で渡す手順を `docs/INSTALL.md` に明記する。経路は2つ:
  - インストール時に CLI: `once install --image ghcr.io/webuilder240/beams:latest --env RAILS_MASTER_KEY=<value> ...`
  - インストール後に TUI: Settings → Environment フォームで `RAILS_MASTER_KEY` を行追加
  (`docs/INSTALL.md`)
  - 受け入れ条件: 上記2経路が `docs/INSTALL.md` に手順として記載され、ローカル `once` で手順通り起動できる
- [ ] ONCE が渡しうるが Beams が使わない env（`VAPID_*` / `SMTP_*` / `NUM_CPUS`）の取扱いを文書化（無視で問題ないことを確認） (`docs/INSTALL.md`)
  - 受け入れ条件: 文書に「現状無視」が明記されている

## グループ C. `/hooks/pre-backup` 実装

- [ ] `bin/hooks/pre-backup` を新規作成。SQLite Online Backup API（`sqlite3` gem の `Database#backup`）を使い、4 つの SQLite（main / cache / queue / cable）の整合性スナップショットを `/storage/backups/once-pending/` に書き出す Ruby スクリプト。実行権限 755 (`bin/hooks/pre-backup`)
  - 受け入れ条件: TDD。`spec/bin/hooks/pre_backup_spec.rb` で 4DB すべてが書き出され、`PRAGMA integrity_check` が `ok` を返すことを検証
- [ ] ロジック本体は `lib/beams/once/pre_backup.rb` の PORO に分離（`bin/hooks/pre-backup` は薄いラッパー）。サービスクラス禁止のため `lib/` 配下 (`lib/beams/once/pre_backup.rb`, `spec/lib/beams/once/pre_backup_spec.rb`)
  - 受け入れ条件: TDD spec が green、カバレッジ 85%+ 維持
- [ ] `Dockerfile` で `bin/hooks/pre-backup` を `/hooks/pre-backup` にコピーし、実行権限を付与 (`Dockerfile`)
  - 受け入れ条件: `docker build` 成功、`docker run --rm <image> ls -l /hooks/pre-backup` で実行権限確認
- [ ] `/hooks/post-restore` の要否を検討。`once-pending` ディレクトリの掃除が必要なら同様に追加（不要なら本タスクを「不要と判断」コメント付きでクローズ） (`bin/hooks/post-restore` or 判断ログ)
  - 受け入れ条件: 判断結果がトピックファイルまたは進捗ログに記載
- [ ] `lib/beams/backup.rb` / `rake beams:backup` / `bin/beams-backup` / `bin/beams-restore` は**維持**（手動緊急時用）。ただし `config/recurring.yml` の `BackupJob` 定期 enqueue を撤去し、自動バックアップは ONCE に一本化する (`config/recurring.yml`, `app/jobs/backup_job.rb` 周辺)
  - 受け入れ条件: `config/recurring.yml` から BackupJob のエントリが消え、関連 spec が green。`rake beams:backup` 単体は引き続き動作する spec が残っている
- [ ] `docs/INSTALL.md` / `docs/RESTORE.md` に「自動バックアップは ONCE TUI で設定する。`rake beams:backup` / `beams:restore` は緊急時の手動世代管理用に維持」と方針を明記 (`docs/INSTALL.md`, `docs/RESTORE.md`)
  - 受け入れ条件: 両ドキュメントに方針記述あり

## グループ D. 旧 `deploy/once/*` 撤去

- [ ] `deploy/once/install.sh` を削除 (`deploy/once/install.sh`)
- [ ] `deploy/once/once-update.service` / `once-update.timer` を削除 (`deploy/once/`)
- [ ] `bin/once-update` を削除 (`bin/once-update`)
- [ ] `lib/beams/once/updater.rb` および `spec/lib/beams/once/updater_spec.rb` を削除 (`lib/beams/once/updater.rb`, `spec/lib/beams/once/updater_spec.rb`)
- [ ] `docs/tasks/18-once-distribution.md` のステータスは ✅完了 のまま据え置き、本ファイル背景節へのリンクで「26 が代替・全撤去」と相互参照 (`docs/tasks/18-once-distribution.md`)
- [ ] `grep -rE 'deploy/once|once-update|TlsConfig|Beams::Once::Updater'` がコード/設定で 0 件になることを確認（docs/tasks は除外） (root)
  - 受け入れ条件: grep 結果が 0 件、`rspec` green、`rubocop` clean

## グループ E. ghcr.io への公開 CI

- [ ] `.github/workflows/release.yml`（新規）を追加。`main` への push 時に `docker/build-push-action` で multi-arch（amd64 + arm64）イメージをビルドし `ghcr.io/webuilder240/beams` に push。タグは **`:latest` と `:<git-sha>` の 2 つ**（git tag 連動は当面なし、必要になったら追加） (`.github/workflows/release.yml`)
  - 受け入れ条件: feature ブランチで workflow_dispatch を実行 → ghcr.io に `:latest` と `:<sha>` の 2 タグが上がる
- [ ] `GITHUB_TOKEN` に `packages: write` 権限を `permissions:` ブロックで付与。secrets は不要 (`.github/workflows/release.yml`)
- [ ] イメージへの OCI labels（`org.opencontainers.image.source` 等）を付与し、GHCR の repo 紐付けを有効化 (`.github/workflows/release.yml`)
- [ ] `README.md` および `docs/INSTALL.md` にプル元 URL（`ghcr.io/webuilder240/beams:latest`）を記載 (`README.md`, `docs/INSTALL.md`)
  - 受け入れ条件: 実 URL が記載されており、`docker pull` で取得できる

## グループ F. `docs/INSTALL.md` を ONCE 手順に刷新

- [ ] 旧手順（`deploy/once/install.sh` / `bin/once-update` / systemd timer）の節をすべて削除 (`docs/INSTALL.md`)
- [ ] 新手順を追記:
  - インストール: `curl https://get.once.com | sh` → `once` → "Enter a Docker image path" で `ghcr.io/webuilder240/beams:latest` → hostname 入力 → DNS A レコード設定の前提を明記
  - 初期 env: ONCE TUI から `RAILS_MASTER_KEY` を custom env として追加する手順
  - バックアップ: ONCE の自動バックアップ設定（保存先・頻度）を TUI で設定。手動は `once` の action menu
  - アップデート: ONCE 内蔵の自動アップデートに任せる。手動更新は CLI コマンド
  - ロールバック: ONCE の機能 or イメージタグ固定の手順
  (`docs/INSTALL.md`)
  - 受け入れ条件: 手順通りに新規 Linux 環境で起動できる（ユーザー環境で実機確認）
- [ ] `CLAUDE.md` のデプロイ節を「ONCE プラットフォーム（basecamp/once）で配布。設置手順は `docs/INSTALL.md` 参照」に更新 (`CLAUDE.md`)
- [ ] `docs/PRODUCT_PLAN.md` §2 配布形態を ONCE プラットフォーム採用に更新 (`docs/PRODUCT_PLAN.md`)
  - 受け入れ条件: 文中に「basecamp/once」「自前 install.sh は撤去」が明記されている

---

## 受け入れ条件（全タスク共通）

`CLAUDE.md` のコーディング制約に従う:

1. **TDD**（Red → Green → Refactor）。テスト後追い禁止
2. テスト通過まで完了にしない（対象 rspec が green、既存テスト破壊なし）
3. service クラス／`app/services` ディレクトリ禁止、`*Service` 命名禁止。新規ロジックは PORO（`app/models/`）or `lib/beams/`、テストは `spec/models/` or `spec/lib/`
4. **SimpleCov カバレッジ 85% 以上**を維持
5. `bin/rubocop` clean（`rubocop-rails-omakase` 準拠）

## DB マイグレーション

**なし**。env 規約と Docker/CI 周りの改修のみ。`docs/tasks/migrations/26-*.md` は不要。

---

## 未決事項（実装前に決める）

1. ~~**ONCE の custom env 追加 UI 仕様**~~ → **✅確定（2026-06-06）**
   - basecamp/once main 実コードで確認済み:
     - TUI: `internal/ui/settings_form_environment.go` の Settings → Environment フォームで任意 key/value を追加可能（`settings.EnvVars map[string]string`）
     - CLI: `internal/command/settings_flags.go` で `--env KEY=VALUE`（繰り返し可）フラグあり
   - 採用方針: B グループは「custom env で `RAILS_MASTER_KEY` を渡す」で確定。credentials 撤去分岐は不要
2. ~~**ghcr.io の publish 先**~~ → **✅確定（2026-06-06）**
   - パス: `ghcr.io/webuilder240/beams`
   - 可視性: **public**（OSS 配布のため認証不要で `docker pull` 可能）
   - 権限: ワークフローの `permissions:` で `packages: write` を付与。リポジトリ Settings → Actions → Workflow permissions が `Read and write` であることを着手時に確認（マネージャー）
3. ~~**イメージタグ運用方針**~~ → **✅確定（2026-06-06）**
   - main push ごとに `:latest` + `:<git-sha>` の 2 タグを push
   - ONCE は `:latest` を pull。不具合時は ONCE TUI でイメージパスを `ghcr.io/webuilder240/beams:<旧 sha>` に固定してロールバック
   - git tag による `:vX.Y.Z` リリース運用は当面なし（必要になったら追加）
4. ~~**`/hooks/pre-backup` 実装方式**~~ → **✅確定（2026-06-06）**
   - **案 a を採用**: SQLite Online Backup API（`sqlite3` gem の `Database#backup`）を Ruby スクリプトで直接呼び、4DB（main / cache / queue / cable）を `/storage/backups/once-pending/` に安全コピー
   - 稼働中の latency 影響を最小化（ONCE のフック設計意図に沿う）
   - PORO は `lib/beams/once/pre_backup.rb`、ラッパーは `bin/hooks/pre-backup`、TDD spec は `spec/lib/beams/once/pre_backup_spec.rb`
5. ~~**既存 `lib/beams/backup.rb` / `rake beams:backup` の扱い**~~ → **✅確定（2026-06-06）**
   - `lib/beams/backup.rb` / `rake beams:backup` / `bin/beams-{backup,restore}` は **維持**（手動緊急時用）
   - `config/recurring.yml` の `BackupJob` 定期 enqueue は **撤去**（自動バックアップは ONCE に一本化）
   - 文書方針を `docs/INSTALL.md` / `docs/RESTORE.md` に明記
6. **トピック18 の記録**
   - `docs/tasks/18-once-distribution.md` は ✅完了 のまま据え置き、本ファイルに「26 で代替・全撤去」と相互参照する方針で確定（**承認済み**）
7. ~~**`config/credentials.yml.enc` の中身棚卸し**~~ → **✅確定（2026-06-06）**
   - 中身:
     - `secret_key_base`（ONCE が `SECRET_KEY_BASE` env を渡すので env が優先される。credentials 側は実質無視）
     - `active_record_encryption.primary_key` / `deterministic_key` / `key_derivation_salt`（AR Encryption の必須キー 3 点。**`RAILS_MASTER_KEY` での復号必須**）
   - 結論: `RAILS_MASTER_KEY` を ONCE custom env で渡す方針で動作する
   - 将来選択肢（メモ）: credentials 撤去するなら AR Encryption を `ACTIVE_RECORD_ENCRYPTION_*` env から読む構成に切替可能。今回は不要
