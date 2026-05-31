# マネージャー管理ログ — トピック18: KamalからONCE配信への移行

> Coder の実装ログ（`docs/tasks/progress/18-*.md`）とは別の、マネージャーによる管理・実測検証ログ。偽の数値・ハッシュは書かない。

- **タスク定義**: [docs/tasks/18-once-distribution.md](../18-once-distribution.md)
- **ブランチ**: `feat/18-once-distribution`（worktree 隔離で Coder 作業）
- **体制**: マネージャー1 / Coder 1 / Tester 1

## ボス決定事項（2026-05-31）

- Kamal 関連成果物は**完全撤去**（`config/deploy.yml`・`bin/kamal`・`.kamal/`・`Gemfile` の `gem "kamal"`）
- 配布物範囲: **インストーラ＋手順書＋TLS自動証明＋自動アップデート**
- 記録: **新タスク18で分解**
- 未決①イメージ: **プレースホルダ変数 `IMAGE`（`ghcr.io/REPLACE_ME/beams:latest`）で保留**
- 未決②更新前バックアップ: **実行する**（`once-update.service` の `ExecStartPre`）
- 未決③`RAILS_MASTER_KEY` 受け渡し: **ホスト env ファイル方式**（`/etc/beams/beams.env` を `--env-file` で共通参照）← マネージャー判断
- 未決④更新間隔: **daily 固定**

## 基線（着手前の実測）

- `bin/rails db:test:prepare` 実行済み
- `bundle exec rspec`: **509 examples, 0 failures**、Line Coverage **98.88% (975/986)**（2026-05-31 マネージャー実測）

## 実行サイクル記録

| グループ | 内容 | 状態 | マネージャー実測 |
|---|---|:---:|---|
| A | Kamal 撤去 | 未着手 | - |
| B | TLS 自動証明（Thruster・TDD） | 未着手 | - |
| C+D | インストーラ＋自動アップデート | 未着手 | - |
| E | INSTALL.md・索引更新 | 未着手 | - |

（各サイクルで: Coder 完了 → コミット実在 `git cat-file -t` → `db:test:prepare`＋`rspec`＋`rubocop` 再現 → 要件 grep 確認 → Tester QA → Reviewer → 完了化、を記録）
