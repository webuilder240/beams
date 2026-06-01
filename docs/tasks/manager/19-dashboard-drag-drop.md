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
| 全体 | D&D並び替え実装（importmap+Stimulus / routes+model / controller / views / test移行） | ✅Coder完了・マネージャー検証済 | 下記参照 |

## マネージャー実測検証（2026-06-01）

Coder（worktree `agent-a5f693816eb9d756e`、ブランチ `feat/19-dashboard-drag-drop`）の報告を実測で再現。

- **コミット実在**: 7件すべて `git cat-file -t` で commit 確認、`feat/19-dashboard-drag-drop` に所属（`8b393be` 分解docの上に積層）。
  - `254475a` importmap+JS / `a823e05` routes+models / `af14d56` controller / `d099fdc` views / `bae32f1`・`5243fa5` test / `0d58571` 実装ログ
- **非system フルスイート**（`rspec --exclude-pattern "spec/system/**/*"`、`db:test:prepare` 後）: **433 examples, 0 failures**、Line Coverage **98.67% (961/974)**。基線（433/0, 98.68%）からリグレッションなし。
- **system spec**（`spec/system/dashboards_spec.rb`, Playwright）: **9 examples, 0 failures**。
- **`bin/rubocop`**: **145 files inspected, no offenses detected**。
- **要件外/逆実装チェック**: `grep -rn "move_up|move_down|swap_with" app/ config/routes.rb spec/` → 残存なし（旧「上へ/下へ」完全撤去を確認）。
- **要件充足（実読確認）**:
  - `config/importmap.rb`: `pin "sortablejs", to: "https://esm.sh/sortablejs@1.15.6"`（esm.sh方式）✓
  - `app/javascript/controllers/sortable_controller.js`: SortableJS適用、`onEnd`でDOM順→`widget_ids[]`をPATCH（CSRF/Turbo Stream受信）✓
  - `config/routes.rb`: `collection { patch :reorder }`、`member move_up/down` 削除 ✓
  - `Dashboard#reorder_widgets!`: 所属IDのみフィルタ・0始まり連番・トランザクション ✓ / `Widget#move_up!`系 削除 ✓
  - `WidgetsController#reorder`: `params[:widget_ids]`受け→`reorder_widgets!`→Turbo Stream再描画。`set_widget`対象から move 系除外 ✓
  - ビュー: 上へ/下へボタン削除・`drag-handle`追加・`data-widget-id`付与・削除ボタン維持、グリッドに `data-controller="sortable"`+`data-sortable-url-value` ✓
- **DBマイグレーション**: なし（`position` 既存）。承認ゲート対象外。

### マネージャー所見・要追跡（Tester/Reviewerへ申し送り）

- **system spec のD&D忠実度**: 並び替えテストは SortableJS の実ドラッグを発火させず、JSで DOM を並べ替えてから `ctrl.onEnd()` を**直接呼ぶ**方式（Coderコメント: Capybara/Playwrightのポインタ操作では発火が不安定なため）。「reorder送信→position永続化→リロード保持」は検証できるが、「SortableJSで実際にドラッグできるか（handle/draggable設定の妥当性）」は未検証。タスク受け入れ条件「Playwrightで実D&D」に対する忠実度をTesterが評価し、Reviewerにも見解を求める。

## Tester QA結果（2026-06-01、Tester独立検証）

- Tester自身の実測: 全スイート `bundle exec rspec` **510 examples, 0 failures**、SimpleCov **98.87%**。`bin/rails routes | grep widget` で reorder/create/destroy のみ（move 系なし）。
- 受け入れ条件1〜7: **全てPASS**（実装本体＝モデル/コントローラ/ルート/ビューは要件充足）。
- **D&D忠実度: 要修正（受け入れ条件未達）**。system spec の並び替えテストが DOM 直接操作＋`onEnd()` 直呼びで、SortableJS の実ドラッグ・`handle` 設定の機能を未検証。タスク受け入れ条件「Playwrightで実D&Dを行い順序が変わることを検証」に対し未達。
- **総合判定: 要修正**（修正点は system spec の1点のみ。実装ロジックは修正不要）。
- **マネージャー処置**: フロー通り Coder に差し戻し。system spec を Playwright の実ポインタ操作（`with_playwright_page` 経由の mouse down→move→up）で SortableJS に実ドラッグを発火させる方式へ修正させる（SortableJS は既定で HTML5 ネイティブ drag のため、合成マウスイベントで駆動するには `forceFallback: true` 併用が有効）。
