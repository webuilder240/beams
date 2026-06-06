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
