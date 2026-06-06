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
| C | `/hooks/pre-backup` 実装 | 未着手 | — |
| D | 旧 `deploy/once/*` 撤去 | 未着手 | — |
| E | GHCR 公開 CI（release.yml） | 未着手 | — |
| F | `docs/INSTALL.md` を ONCE 手順に刷新 | 未着手 | — |

## Tester QA（予定）

- 全グループ Coder 完了・マネージャー実測検証後に 1 回実施。

## Reviewer（予定）

- Tester PASS 後に `reviewer` スキルで品質レビュー。

## マイグレーション

- **なし**（env 規約 / Docker / CI / docs のみ）。承認ゲート対象外。
