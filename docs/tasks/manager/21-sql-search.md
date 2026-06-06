# マネージャー管理ログ — トピック21: クエリ本文の SQL 検索（LIKE）

> Coder の実装ログ（`docs/tasks/progress/21-sql-search.md` は本トピックでは作成なし — 実装が小規模・1 サイクルで完了したため `docs/tasks/21-sql-search.md` のチェックボックス更新のみで代替）とは別の、マネージャーによる管理・実測検証ログ。偽の数値・ハッシュは書かない。

- **タスク定義**: [docs/tasks/21-sql-search.md](../21-sql-search.md)
- **ブランチ**: `feat/21-sql-search`（worktree `.claude/worktrees/feat-21-sql-search` で Coder 作業）
- **体制**: マネージャー1 / Coder 1 / Tester+Reviewer 兼任 1

## ボス決定事項（2026-06-06 確定済み）

| ID | 決定 |
|---|---|
| B1 | 既存の単一入力欄を「タイトル＋SQL本文」のOR検索に変更（placeholder のみ更新） |
| B2 | `Query.title_matching` を `text_matching` にリネームし、`title OR sql_body` の OR 検索化 |
| B3 | ダッシュボード一覧は従来通りタイトル検索のまま（Dashboard.title_matching は維持） |

## 基線（着手前の実測、main `97d952f` 時点）

- `bundle exec rspec`: 513 examples / 0 failures、Line Coverage 98.88%
- `bin/rubocop`: 147 files / no offenses

## 実行サイクル記録

| グループ | 内容 | 状態 | マネージャー実測 |
|---|---|:---:|---|
| 全体 | scope リネーム＋OR検索化 / コントローラ追随 / view placeholder / spec 追加 | ✅Coder完了・Tester+Reviewer PASS・マネージャー検証済 | 下記参照 |

## マネージャー実測検証（2026-06-06）

Coder（worktree `feat-21-sql-search`、ブランチ `feat/21-sql-search`）の報告を実測で再現。

### コミット実在（`git cat-file -t` 確認済）

- `ad4d3f7` feat(21-sql-search): title_matching を text_matching にリネームし OR 検索化
- `9a34187` test(21-sql-search): SQL本文検索のリクエスト/システムテスト追加
- `fe742dd` docs(21-sql-search): タスクチェックボックスを完了状態に更新

### 実測値

- `bundle exec rspec`: **519 examples / 0 failures**（基線 513 → +6 model spec を `title_matching` から `text_matching` に置換し title-only / sql_body-only / 両方 / 不一致 / 空・nil / `%` / `_` / `\` エスケープを 8 ケース、request spec に SQL 本文一致、system spec に rack_test E2E を追加）
- Line Coverage: **98.88% (974/985)**、閾値 85% クリア
- `bin/rubocop`: 147 files / no offenses
- `grep -rn "title_matching" app/ spec/`: `Query` 側 0 件 / `Dashboard` 側 8 件（B3-A の意図的保持）

### 要件外/逆実装チェック

- `app/services/` 不在・`*Service` 命名なし
- DB 変更なし（マイグレーション承認ゲート対象外）
- `app/models/query.rb#text_matching`: `sanitize_sql_like` + 名前付きバインド `:p` + `ESCAPE '\\'` で SQL Injection / LIKE 特殊文字（`%`/`_`/`\`）を安全化
- `app/views/queries/index.html.erb` placeholder「タイトル/SQL本文で検索」
- `app/controllers/queries_controller.rb#index`: `Query.text_matching(params[:q])` で動作

## Tester + Reviewer 結果（2026-06-06、兼任）

タスクが小規模（実装 3 コミット）のため Tester と Reviewer を兼任。

- 受け入れ条件 7/7（ゴール）・タスク受け入れ条件・動作確認 8/8 すべて **PASS**
- ボス決定 B1〜B3 すべて反映
- **Reviewer findings**: must 0 / should 0 / nice-to-have 6（テスト fixture 強化案 N1/N2、コメント補足 N3、共通化検討 N4 — YAGNI で見送り、パフォーマンス参考 N5、命名 N6 — B2 確定済みで受容）
- **総合判定: PASS（条件なし）**

### ボス判断（マネージャー代理）

- nice-to-have は **すべて見送り**（実害なし・タスク仕様で許容済み・命名は B2 確定）
- マージブロッカーなし

## 完了化

- `docs/tasks/00-overview.md` の 21 行ステータスを `✅完了` に更新
- `docs/tasks/PROGRESS_LOG.md` の 21 行を `✅完了 / Coder/Tester+Reviewer / manager/21-sql-search.md` に更新
- ブランチ `feat/21-sql-search` は worktree 内に残置。PR 作成は**ユーザー指示時のみ**実施

## 最終実測値（再現済み）

| 指標 | 値 |
|---|---|
| `bundle exec rspec` | 519 examples / 0 failures |
| Line Coverage | 98.88% (974/985)、閾値 85% クリア |
| `bin/rubocop` | 147 files / no offenses |
| `feat/21-sql-search` コミット数 | 3（feat 1 + test 1 + docs 1） |
