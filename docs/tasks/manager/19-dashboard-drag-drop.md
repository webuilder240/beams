# マネージャー管理ログ — トピック19: ダッシュボードのドラッグ&ドロップ並び替え

> Coder の実装ログ（`docs/tasks/progress/19-*.md`）とは別の、マネージャーによる管理・実測検証ログ。偽の数値・ハッシュは書かない。

- **タスク定義**: [docs/tasks/19-dashboard-drag-drop.md](../19-dashboard-drag-drop.md)
- **ブランチ**: `feat/19-dashboard-drag-drop`（worktree 隔離で Coder 作業）
- **体制**: マネージャー1 / Coder 1 / Tester 1 / Reviewer

## ボス決定事項（2026-06-01）

- **D&D 実現方式**: SortableJS を importmap に pin（esm.sh、既存 Chart.js/CodeMirror と同方針）＋ Stimulus コントローラでラップ。Vue/React 等のリアクティブライブラリは不使用。
- **既存「上へ/下へ」ボタンは D&D に置き換える**（`move_up`/`move_down` のルート・アクション・モデルメソッドを削除）。→ 並び替えは JS 必須化。
- **永続化は一括並び替えエンドポイント新設**: `PATCH /dashboards/:dashboard_id/widgets/reorder`（widget ID 順序配列で position 一括更新）。
- **DB マイグレーション不要**: `position` カラムは既存（トピック12）。承認ゲート対象外。

## 基線（着手前の実測、2026-06-01 マネージャー実測）

- `bin/rails db:test:prepare` 実行済み
- 非 system フルスイート（`rspec --exclude-pattern "spec/system/**/*"`）: **433 examples, 0 failures**、Line Coverage **98.68% (973/986)**
- 対象既存 spec（widget/dashboard model + request）: 55 examples, 0 failures

## 実行サイクル記録

| グループ | 内容 | 状態 | マネージャー実測 |
|---|---|:---:|---|
| — | （Coder 着手前） | 🚧 | — |
