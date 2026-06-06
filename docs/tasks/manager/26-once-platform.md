# マネージャー管理ログ — トピック26: ONCE プラットフォームへの移行（basecamp/once 採用）

> Coder の実装ログ（`docs/tasks/progress/26-once-platform.md`）とは別の、マネージャーによる管理・実測検証ログ。偽の数値・ハッシュは書かない。

- **タスク定義**: [docs/tasks/26-once-platform.md](../26-once-platform.md)
- **ブランチ**: `feat/26-once-platform`（worktree 隔離で Coder 作業）
- **体制**: マネージャー1 / Coder 1 / Tester 1 / Reviewer 1

## ボス決定事項（2026-06-06）

- 実装単位: **1 ブランチ `feat/26-once-platform` 直列**。A → B → C → D → E → F の順に Coder を直列起動し、グループ毎にコミット。Tester / Reviewer はブランチ全体完了後にまとめて 1 回（トピック18 と同方針）。
- グループ E（GHCR 公開 CI）: **release.yml のファイル追加までで完了**。actionlint / YAML パースで構文検証。実 publish はマージ後ユーザーが手動 workflow_dispatch で確認（トピック18 と同じ「実機確認はユーザー側」方針）。
- グループ F（INSTALL.md 刷新）: **旧手順は完全削除して ONCE 手順に置換**。旧版は git 履歴に残るため付録は不要。
- タスクファイル末尾の未決事項 1〜5・7 は分解時に確定済み（タスクファイル参照）。未決6（トピック18 据え置き相互参照）も確定済み。

## 基線（着手前の実測・2026-06-06）

- `bin/rails db:test:prepare` 実行済み
- `bundle exec rspec`: **546 examples, 0 failures**、Line Coverage **98.66% (1031/1045)**（マネージャー実測）
- 撤去対象ファイル実在を確認:
  - `deploy/once/install.sh` / `deploy/once/once-update.service` / `deploy/once/once-update.timer`
  - `bin/once-update`
  - `lib/beams/once/tls_config.rb` / `lib/beams/once/updater.rb`
  - `spec/lib/beams/once/tls_config_spec.rb` / `spec/lib/beams/once/updater_spec.rb`
- `Dockerfile` の `EXPOSE 80` + `EXPOSE 443` も実在確認
- `config/recurring.yml` に `daily_backup` (`BackupJob`) 定期 enqueue 実在確認

## 実行サイクル記録

| グループ | 内容 | 状態 | マネージャー実測 |
|---|---|:---:|---|
| A | Thruster TLS 撤去・port 80 専用化 | ✅完了 | コミット `30a1616` / `7afb089` / `acd4732` / `1960c43` 実在確認。`lib/beams/once/tls_config.rb` と `spec/lib/beams/once/tls_config_spec.rb` 削除（B で `DISABLE_SSL` 反転判定 spec を新設予定）、`production.rb` の TlsConfig 参照／`assume_ssl`／`force_ssl` ブロック撤去、`Dockerfile` は `EXPOSE 80` のみで `EXPOSE 443`／`HTTPS_PORT` 言及なし。`docs/INSTALL.md` の `TLS_DOMAIN`／`HTTPS_PORT` 言及撤去（CLAUDE.md は元々言及なし）。マネージャー実測: `rspec` **540 examples / 0 failures**、Line Coverage **98.65% (1021/1035)**、`rubocop` **155 files inspected, no offenses**。`updater.rb` の `HTTPS_PORT = "443:443"` は D で `updater.rb` ごと撤去予定のため残置 |
| B | ONCE 環境変数規約への対応（DISABLE_SSL） | ✅完了 | コミット `cd02ed1` / `d6994a6` / `9836f5b` 実在確認。`Beams::Once::SslMode` PORO 新設（`lib/beams/once/ssl_mode.rb`）、TDD（Red: LoadError → Green）。`DISABLE_SSL=="true"` のとき無効、それ以外（未設定／空文字／その他）で有効、`ssl_options` で `/up` を https リダイレクトから除外。`production.rb` で SslMode 利用して `assume_ssl` / `force_ssl` / `ssl_options` を本実装に置換。`RAILS_MASTER_KEY` 空での boot 検証: `env -u RAILS_MASTER_KEY bundle exec rails runner 'p :ok'` → `:ok`（マネージャー再現）。`docs/INSTALL.md` に「ONCE 環境変数」節を追記（VAPID_*／SMTP_*／NUM_CPUS は無視で OK と明記、RAILS_MASTER_KEY の CLI/TUI 経路2つ記載）。マネージャー実測: `rspec` **548 examples / 0 failures**、Line Coverage **98.66% (1030/1044)**、`rubocop` **157 files, no offenses** |
| C | `/hooks/pre-backup` 実装 | ✅完了 | コミット `4097d0e` / `7bfc6cd` / `c131b51` / `6eb7038` 実在確認。`Beams::Once::PreBackup` PORO 新設（`Beams::Backup.default_sources` を流用、4 DB を `VACUUM INTO` で `/storage/backups/once-pending/` に整合性スナップショット）、TDD（Red: LoadError → Green）。`bin/hooks/pre-backup` を Rails 非依存ラッパーで作成（`ls -l` で `-rwxr-xr-x` 確認）。Dockerfile 最終ステージで `mkdir /hooks` → `cp` → `chmod 755` → `chown rails:rails` で `/hooks/pre-backup` 配置。`config/recurring.yml` から `daily_backup` (`BackupJob`) を撤去、`clear_solid_queue_finished_jobs` は維持、撤去理由コメント残置。`spec/config/recurring_spec.rb` も BackupJob 不在検証に更新。`/hooks/post-restore` は不要と判断（once-pending は ONCE 側で取得・破棄、Solid* は Rails 起動で復帰）。`docs/INSTALL.md` に「バックアップ（ONCE 統合）」節追加、`docs/RESTORE.md` 冒頭に方針 blockquote 追加（F で本格刷新予定）。マネージャー実測: `rspec` **560 examples / 0 failures**、Line Coverage **98.7% (1062/1076)**、`rubocop` **161 files, no offenses** |
| D | 旧 `deploy/once/*` 撤去 | ✅完了 | コミット `86c9352` / `06ef080` / `4f3064b` 実在確認。`deploy/once/{install.sh,once-update.service,once-update.timer}` / `bin/once-update` / `lib/beams/once/updater.rb` / `spec/lib/beams/once/updater_spec.rb` を `git rm`（6 ファイル）、`deploy/` ディレクトリ自体も空になり消滅。`docs/INSTALL.md` / `docs/PRODUCT_PLAN.md` から旧手順言及を撤去（F での本格刷新は別途）。`docs/tasks/18-once-distribution.md` 冒頭に「26 で全撤去」相互参照 blockquote 追加（ステータス文字列「未着手」は元々の表示不整合のまま残置、F で合わせて整理）。マネージャー実測: `grep -rE 'deploy/once\|once-update\|TlsConfig\|Beams::Once::Updater'`（docs/tasks / .git / .claude / node_modules / coverage 除外）→ **0 件**、`rspec` **554 examples / 0 failures**、Line Coverage **98.93% (1017/1028)**、`rubocop` **159 files, no offenses** |
| E | GHCR 公開 CI（release.yml） | ✅完了（ファイル追加まで・実 publish はマージ後ユーザー手動 workflow_dispatch） | コミット `d3c5f55` / `68f5415` / `a59f6b6` 実在確認。`.github/workflows/release.yml` 新規（main push + workflow_dispatch、multi-arch amd64/arm64、`ghcr.io/webuilder240/beams:latest` + `:${{ github.sha }}`、`docker/build-push-action@v6`、`permissions: contents:read / packages:write`、OCI labels (source/description/revision)、GHA cache、concurrency `release-${{ github.ref }}`/cancel-in-progress）。`actions/checkout@v6` は ci.yml と整合。LICENSE 不在のため `licenses` ラベルは省略。マネージャー実測: `ruby -ryaml YAML.load_file` パース成功（キー `["name", true, "concurrency", "permissions", "jobs"]` — `true` は YAML 1.1 で `on:` をブール化したもので Actions では正常）、`actionlint` は未インストールのためスキップ。`rspec` **554 examples / 0 failures**、Line Coverage **98.93% (1017/1028)**、`rubocop` **159 files, no offenses**。README / INSTALL.md にプル元 URL 記載済み。GHCR repository settings の `Read and write` 確認はユーザー側（コードからは確認不能） |
| F | `docs/INSTALL.md` を ONCE 手順に刷新 | ✅完了 | コミット `a062447` / `18f3da8` / `5cc91b2` / `35d314d` / `fe8b02a` 実在確認。`docs/INSTALL.md` を全面刷新（暫定 blockquote 全撤去、章 1〜10 連番: 前提 / インストール (TUI+CLI 経路) / 初期 env / バックアップ (自動 ONCE 統合・手動緊急時用) / アップデート / ロールバック / ポート / 環境変数 (Beams 利用 / ONCE 由来未使用) / ヘルスチェック / 関連ドキュメント）。`CLAUDE.md` デプロイ節を「ONCE プラットフォーム（basecamp/once）で配布。設置手順は `docs/INSTALL.md` 参照」へ更新。`docs/PRODUCT_PLAN.md` §2 配布形態 / §2.2 Thruster 役割（SSL 終端を ONCE 側に委ねる旨）/ §3 技術スタック表 Webサーバ行を整合。`README.md` を ONCE 配布前提で簡素化（Rails 標準 plant text 削除、Bugsnag 行は `.kamal/secrets` → ONCE custom env に修正）。`docs/tasks/18-once-distribution.md:7` のステータス文字列を「✅完了（履歴・トピック26 で全撤去）」に修正。マネージャー実測: `rspec` **554 examples / 0 failures**、Line Coverage **98.93% (1017/1028)**、`rubocop` **159 files, no offenses** |

## Tester QA（ブランチ全体・2026-06-06）

- 担当: tester-26（要件 QA、ファイル非編集）
- 結果: **全項目 PASS**。グループ A〜F の全チェック項目を `ls`・`grep`・`Read` で 1 つずつ照合し合致。
  - `env -u RAILS_MASTER_KEY bundle exec rails runner 'p :ok'` を Tester 自身で実行し `:ok` 確認（B: RAILS_MASTER_KEY 未設定でも boot 通る）
  - `grep -rE 'deploy/once|once-update|TlsConfig|Beams::Once::Updater'`（docs/tasks / .git / .claude / coverage / node_modules 除外）→ **0 件**（D: 全撤去達成）
  - `ruby -ryaml -e 'YAML.load_file(".github/workflows/release.yml")'` パース成功（E: YAML 構文 OK）
  - `bin/hooks/pre-backup` が `-rwxr-xr-x` (755) / shebang `#!/usr/bin/env ruby` を実機確認（C: 実行権限・ラッパー）
- 横断: `rspec` 554/0/カバレッジ 98.93%（リファクタ前）。気になる点として PRODUCT_PLAN §2.2 の「HTTP/2」表記が TLS 終端 ONCE 化に伴い h2c 想定が妥当（Reviewer N6 で扱う）と申し送り。

## Reviewer（ブランチ全体・2026-06-06）

- 担当: reviewer-26（コード品質・設計制約・重複/単純化/効率、ファイル非編集）
- 結果: **must 2 件 / should 8 件 / nice-to-have 7 件**。サービスクラス禁止厳守・PORO/lib 配置・spec 配置は健全。must 対応でマージ可能水準。
- マネージャー選定の対応方針:
  - **対応**: M1 (RESTORE.md 自己矛盾)、M2 (PreBackup cwd 依存)、S1 (Dockerfile COPY 一行)、S3 (OCI labels title/created 追加)、S4 (cancel-in-progress: false)、S6 (`Beams::Backup.snapshot` 共通化)、S7 (`bundler/setup` 追加)、N1 (`SslMode SSL_OPTIONS` 定数化)、N6 (PRODUCT_PLAN HTTP/2 → h2c)
  - **見送り**: S2（タスク仕様が 2 タグ運用を明示）、S5（private stub・動作上問題なし）、S8（hook spec grep・動作上問題なし）、N2/N3/N4/N5/N7（重要度低・運用議論）。判断は本表内に記載済み。

## リファクタ（Reviewer 対応・2026-06-06 マネージャー再現）

- コミット `a0686bf`（M1）／`808657f`（M2＋S7）／`10e6732`（S6）／`42aaacb`（S1）／`b4d165b`（S3＋S4）／`671409d`（N1＋N6）／`66f2434`（進捗ログ追記）実在確認。
- マネージャー実測再現:
  - `bin/hooks/pre-backup` 冒頭に `Dir.chdir(File.expand_path("../..", __dir__))` ＋ `require "bundler/setup"` を確認（M2/S7）
  - `Dockerfile` の `/hooks/pre-backup` 配置は `COPY --chmod=0755 --chown=rails:rails bin/hooks/pre-backup /hooks/pre-backup` 一行へ整理。USER root↔1000 切替が撤去（S1）
  - `.github/workflows/release.yml`: `concurrency: cancel-in-progress: false`、OCI labels に `title=Beams` ＋ `created=${{ github.event.head_commit.timestamp }}` 追加（S3/S4）
  - `lib/beams/backup.rb` に `Beams::Backup.snapshot(source_path:, dest_path:)` クラスメソッドを追加、`Beams::Once::PreBackup` から呼び出し（S6 重複解消、PORO 範囲内）
  - `Beams::Once::SslMode::SSL_OPTIONS` 定数化（N1）、`docs/PRODUCT_PLAN.md` §2.2 HTTP/2 → 「HTTP（h2c も可）」へ修正（N6）
- 最終再現値: `rspec` **559 examples / 0 failures**、Line Coverage **98.92% (1005/1016)**、`rubocop` **159 files, no offenses**。

## 完了判定（2026-06-06）

- グループ A〜F の全チェックボックス完了。Tester 全項目 PASS、Reviewer must 0 件・選定 should/nice-to-have 対応済み（見送り判断は管理ログに記録）。
- 最終 `rspec` **559 examples / 0 failures**・Line Coverage **98.92% (1005/1016)** ≥ 85%・`rubocop` **no offenses**・`grep` 旧層 0 件（docs/tasks 除外）を**マネージャー自身で再現確認**。
- ブランチ `feat/26-once-platform`（グループコミット列＋リファクタコミット列）。**push/PR/マージはユーザー指示待ち**（未実施）。
- 残: 実機動作確認（ONCE TUI での実 install / GHCR への workflow_dispatch publish / `/hooks/pre-backup` 実コール）はユーザー環境で実施。GHCR repository 設定（Actions Workflow permissions が `Read and write`）の確認はユーザー側のみ可能。

## マイグレーション

- **なし**（env 規約 / Docker / CI / docs のみ）。承認ゲート対象外。
