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
| A | Kamal 撤去 | ✅完了 | コミット `96fd562` 実在。kamal 残存は docs/tasks のみ・Gemfile.lock kamal=0。worktree で `bin/rubocop` 145 files no offenses、`rspec` 509 examples/0 failures/カバレッジ 98.88%（基線維持）。main 汚染なし。新規ロジック無しのため Tester/Reviewer はマネージャー実測で代替 |
| B | TLS 自動証明（Thruster・TDD） | ✅完了 | コミット `7de3020` 実在。PORO `Beams::Once::TlsConfig`＋spec で TDD(Red:LoadError→Green)。production.rb は `TLS_DOMAIN` 設定時のみ assume_ssl/force_ssl/ssl_options。Dockerfile `EXPOSE 80`+`443`。`rspec` 515 examples/0 failures/カバレッジ 98.9%、`rubocop` no offenses（マネージャー再現） |
| C+D | インストーラ＋自動アップデート | ✅完了 | コミット `1812ddb` 実在。install.sh(set -euo pipefail/env-file 600/冪等)・updater.rb(Rails非依存/DI runner/install.shと同一run引数)・spec(順序pull<stop<rm<run・run引数・no-recreate・共有定数=3 examples Red:LoadError→Green)・systemd(fail-closed backup/daily)。`bash -n`/`ruby -c` OK、`rubocop` no offenses、`rspec` 518 examples/0 failures/カバレッジ 98.66%（マネージャー再現） |
| E | INSTALL.md・索引更新 | ✅完了 | コミット `e582791` 実在。docs/INSTALL.md（9セクション）・00-overview(総数18・行18)・PROGRESS_LOG(行18)・PRODUCT_PLAN §2 追記。`rspec` 518/0/98.66%・`rubocop` clean（マネージャー再現） |

## Tester QA（ブランチ全体・2026-05-31）

- 担当: tester-18（要件QA、ファイル非編集）
- 結果: B〜F は **PASS**。A のみ「docs/tasks 外で kamal 0 件」が `docs/PRODUCT_PLAN.md:46` の地の文「Kamal を廃し」で**1件未達**→ **要修正**。
- 対応: Coder がコミット `c0778ea` で同行を「従来のデプロイ基盤を廃し」へリワード。マネージャー実測 `grep`（docs/tasks 除く）= **0 件**達成、`rspec` 518/0/カバレッジ 98.66%・`rubocop` clean を再現。→ **Tester 全項目 PASS**。
- install.sh ⇔ updater.rb の run 引数・共有定数の完全一致を Tester が突合確認済み。

## Reviewer（ブランチ全体・2026-05-31）

- 担当: reviewer-18（コード品質・設計制約、ファイル非編集）
- 結果: **must 0 件・マージ可能品質**。service クラス禁止・PORO/lib 配置・テスト位置は既存規約と整合。鍵の env ファイル 600 / `--env-file` 経路も妥当。
- should 指摘と対応方針:
  - should-2（機能影響）: updater が env の `IMAGE` を無視し定数 `:latest` 使用 → ロールバック巻き戻しリスク。**対応**（`ENV.fetch("IMAGE", IMAGE)`＋service の `EnvironmentFile`＋spec＋INSTALL.md）。
  - should-1: digest 命名/コメント/INSTALL.md がローカルImage ID の実体と不一致 → **対応**（`*_image_id` へリネーム等）。
  - should-3: 定数pinテストにポート/MOUNT/RESTART_POLICY 追加 → **対応**。
  - should-4: production.rb の TlsConfig 二重生成 → **対応**。
  - nice-to-have 5（timer `Unit=`）・7（未使用 attr_reader）→ **対応**。8（FakeRunner 緩マッチ）→ **見送り**（2キーで実害なし）。
- リファクタ実装は Coder に依頼（マネージャーは実装しない）。リファクタ後の green/カバレッジ/rubocop をマネージャーが再現確認予定。

## リファクタ（Reviewer should 対応・2026-06-01 マネージャー再現）

- コミット `09ad94d` 実在。should-2（updater が `ENV.fetch("IMAGE", IMAGE)` で env の IMAGE を尊重・service に `EnvironmentFile=/etc/beams/beams.env`・spec 追加でロールバック巻き戻し防止）／should-1（`*_image_id` リネーム・doc 整合）／should-3（pin テストに MOUNT/ポート/RESTART_POLICY 追加）／should-4（production.rb の TlsConfig を単一インスタンスに）／nice-to-have（timer `Unit=` 明示・未使用 attr_reader 削除）を反映。FakeRunner は依頼どおり見送り。
- マネージャー実測再現: `bundle exec rspec` **521 examples, 0 failures**、Line Coverage **98.66% (1030/1044)**、`bin/rubocop` **no offenses**、`bash -n install.sh`/`ruby -c bin/once-update` OK、`grep kamal`（docs/tasks 除く）**0 件**、install.sh ⇔ updater.rb の run 引数・共有定数の一致を再確認。production.rb の TlsConfig 生成は 1 箇所。

## 手動「動作確認」項目の状況（タスク末尾4項目）

実イメージ/実環境が前提のため一部のみ実施:
- ✅ `bash -n deploy/once/install.sh`（OK）/ ✅ `ruby -c bin/once-update`（Syntax OK）
- ✅ `systemd-analyze verify`：ユニット構文は妥当（exit 0）。警告2件（`docker.service not found`・`/opt/beams/bin/once-update` 未配置）は本サンドボックス環境依存で INSTALL.md §7 の調整箇所どおり。
- ⏳ `docker build` → `docker run -p 80:80` → `curl /up` 200、`bin/once-update` の実 dry-run：**未実施**。配布イメージ（`IMAGE`）が未確定（プレースホルダ）かつ実 Docker ビルド/レジストリが必要なため、ユーザー環境での実機確認に委ねる。

## 完了判定（2026-06-01）

- グループ A〜F の全チェックボックス完了。Tester 全項目 PASS、Reviewer must 0 件・should 対応済み。
- `rspec` 521/0・カバレッジ 98.66%（≥85%）・`rubocop` clean・kamal 残存 0（docs/tasks 除く）を**マネージャー自身が worktree で再現確認**。
- ブランチ `feat/18-once-distribution`（コミット: `96fd562`→`7de3020`→`1812ddb`→`e582791`→`c0778ea`→`09ad94d`）。**push/PR/マージはユーザー指示待ち**（未実施）。
- 残: 実機の docker build/run スモークテスト（ユーザー環境）と、配布イメージ `IMAGE` の確定。
