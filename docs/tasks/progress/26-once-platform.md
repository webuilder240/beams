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
