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

## Coder 差し戻し対応・マネージャー再検証（2026-06-01）

- Coder 修正コミット **`1f072cf`**（`git cat-file -t` で commit 確認）: `sortable_controller.js` に `forceFallback: true` 追加、system spec を `page.driver.with_playwright_page` 経由の実ポインタ操作（`.drag-handle` を `mouse.down` → `steps:` 付き複数 `mouse.move` → `mouse.up`）へ置換。`insertBefore`/`ctrl.onEnd()` 直呼びは削除（`grep` で残存なし確認）。既存 onEnd→PATCH→Turbo Stream フローは不変。
- **マネージャー実測再現**（worktree、`db:test:prepare`＋`tailwindcss:build` 後）:
  - `spec/system/dashboards_spec.rb`: **9 examples, 0 failures**。D&D単体テストはフレーク確認で**計3回**（Coder1＋マネージャー2）すべて `1 example, 0 failures`。
  - 非system フルスイート: **433 examples, 0 failures**、Line Coverage **98.67% (961/974)**（基線維持）。
  - `bin/rubocop`: **145 files inspected, no offenses detected**。
- **判定**: Tester の唯一の指摘（D&D忠実度）は実ポインタ操作テストで**解消**。実ドラッグの結果として並び替え→PATCH→position永続化→リロード保持を検証できている。→ Tester PASS 相当としてフェーズ6（Reviewer）へ進む。

## Reviewer レビュー結果（2026-06-01、`reviewer` スキル）

- **`must`: なし**。設計制約違反なし（serviceクラス禁止◯ / リアクティブライブラリ不使用◯ / rubocop omakase 準拠）。
- **`should`（マネージャー: 全件対応とする）**:
  - should-1: `Dashboard#reorder_widgets!` のループ内 `update_all` が N+1 SQL → 単一 `CASE WHEN` UPDATE 等へ一括化。
  - should-2: `sortable_controller.js` の `fetch` にエラーハンドリングなし（4xx/5xx・ネットワークエラーで DOM とサーバが無音 desync）→ `response.ok` false で reject＋`.catch` でログ。
  - should-3: Turbo Frame 再描画時の `Sortable` 旧インスタンス参照保持 → `disconnect` で `this.sortable = null` を明示。
  - should-4: system spec の固定 `sleep`（1.0/2.0）がフレーク要因 → DOM 変化を待つポーリング（`have_css` の `wait:` 等）へ置換。
- **`nice-to-have`（マネージャー: 安価で有益な3件を対応とする）**:
  - nth-1: `reorder_widgets!` に「呼び出し元は全ウィジェット ID を送る前提」のコメント明記。
  - nth-2: `onEnd(event)` で `oldIndex === newIndex`（順序不変）のとき fetch をスキップ（無駄な PATCH 防止）。
  - nth-3: `dashboard_spec.rb` のトランザクションテストが名（all-or-nothing）と実体（正常系）の乖離 → 実際にロールバックを検証する内容へ書き直し。
- **マネージャー処置**: 上記 should 4件＋nice-to-have 3件を Coder にリファクタ依頼（外部から見た振る舞いを変えない／green・カバレッジ85%以上・rubocop クリーン維持）。見送り: なし。

## リファクタ完了・マネージャー最終検証（2026-06-01）

- Coder リファクタコミット **`4846f8b`**（`git cat-file -t` で commit 確認）。Reviewer 指摘 should×4・nice-to-have×3 を全件対応（実読確認）:
  - `reorder_widgets!` は単一 `CASE WHEN id=? THEN ? … END` の `update_all`（プレースホルダでパラメータ化＝SQLi 安全）へ一括化。
  - `sortable_controller.js`: `response.ok` false で throw＋`.catch` でログ／`disconnect` で `this.sortable = null`／`onEnd(event)` で `oldIndex===newIndex` 時 fetch スキップ／`connect` で `data-sortable-ready` マーカー（待機判定用 data 属性のみ）。
  - `dashboard_spec.rb`: トランザクションテストを実ロールバック検証（`ActiveRecord::Rollback` で全 position が元値のまま）へ書き直し。
- **マネージャー実測再現**（worktree、`db:test:prepare`＋`tailwindcss:build` 後）:
  - 非system フルスイート: **433 examples, 0 failures**、Line Coverage **98.67% (964/977)**。
  - `spec/system/dashboards_spec.rb`: **9 examples, 0 failures**。D&D 単体（`drag-and-drop`）は**3連続すべて `1 example, 0 failures`**（フレークなし）。
  - `bin/rubocop`: **145 files inspected, no offenses detected**。
- **完了判定**: タスク `19-dashboard-drag-drop.md` の全チェックボックス充足、Tester PASS（D&D忠実度解消）、Reviewer 指摘対応済み、マネージャー再現で green・カバレッジ85%以上・rubocop クリーンを確認。→ **トピック19 完了**。
- 補足: DBマイグレーションなし（承認ゲート対象外）。push/PR は未実施（ユーザー明示依頼時のみ）。

## 追加対応: 保存失敗時のUX（フォローアップ、2026-06-01）

- **ボス決定**: D&D 保存失敗時に (1) 並び順をドラッグ前へ復元、(2) 画面右下のトーストでエラー通知。トーストは汎用機構として新設。
- **ブランチ運用**: 本体作業ツリーは `feat/19-dashboard-drag-drop`（ユーザーがローカル起動中）のまま維持し、派生ブランチ `feat/19-reorder-failure-toast` を切って Coder（worktree隔離 `agent-ae046231b7ed3085f`）が実装。完了後 `feat/19` へ **ff-only マージ**で統合。
- **Coder 実装コミット**（`git cat-file -t` で commit 確認、`feat/19` に統合済み）: `b355495`(system spec RED) / `12f8da7`(toast機構) / `01dab58`(sortable失敗ハンドリング=DOM復元+toast) / `58f569c`・`1b4783c`(進捗ログ)。
- **実装概要**: `toast_controller.js`（`toast:show` カスタムイベント購読・右下固定・4秒自動消滅・手動クローズ・HTMLエスケープ済み・error/notice配色）＋レイアウトに固定コンテナ。`sortable_controller.js` は `onEnd` で `oldIndex/newIndex` から元順序を逆算保持し、失敗時に `_restoreOrder`（appendChild）でDOM復元→`toast:show`(error) 発火。成功系・順序不変スキップは不変。
- **マネージャー実測再現**（worktree、`db:test:prepare`＋`tailwindcss:build` 後）:
  - `spec/system/dashboards_spec.rb`: **11 examples, 0 failures**。新規2例（toast表示・reorder失敗時の復元&トースト）は**3連続すべて `2 examples, 0 failures`**（フレークなし）。
  - 非system フルスイート: **433 examples, 0 failures**、Line Coverage **98.67% (964/977)**。
  - `bin/rubocop`: **145 files inspected, no offenses detected**。
- **判定**: 追加対応の全チェックボックス充足、マネージャー再現で green・カバレッジ85%以上・rubocop クリーン。`feat/19-reorder-failure-toast` は ff マージ済みのため削除。push/PR は未実施（ユーザー明示依頼時のみ）。

## Brakeman リグレッション解消（PR作成前、2026-06-01）

- **検知**: PR 作成準備中のマネージャー実測で `bin/brakeman --no-pager` が **SQL Injection（Weak）1件**（`app/models/dashboard.rb` の `reorder_widgets!` 一括 UPDATE の生SQL補間）。**main 基線は 0 件**＝新規リグレッション。`bin/brakeman` は警告時 exit 非ゼロのため CI `scan_ruby` が赤になる。
- **処置**: 抑制（brakeman.ignore）ではなく**発生源で解消**する方針で Coder（worktree隔離 `agent-a9c34971398102dc0`、派生ブランチ `feat/19-brakeman-fix`）に依頼。
- **Coder 対応コミット**（`git cat-file -t` で commit 確認、`feat/19` に ff 統合済み）: `007d02d`（`reorder_widgets!` を生SQL補間 → `Widget.update(filtered, attrs)` のイディオムへ書き換え）/ `03a0892`（進捗ログ）。`brakeman.ignore` 未使用。契約（所属IDのみ・0始まり連番・トランザクション）は不変。
- **マネージャー実測再現**（worktree、`db:test:prepare`＋`tailwindcss:build` 後）:
  - `bin/brakeman --no-pager`: **Security Warnings 0**（解消確認）。
  - `bundle exec rspec`（全体、system含む）: **512 examples, 0 failures**、Line Coverage **98.87% (964/975)**。
  - `bin/rubocop`: **145 files inspected, no offenses detected**。
  - 注: Coder 報告の「全体で 55 failures」は worktree で `tailwindcss:build` 未実行だったための環境起因（system spec のアセット欠落）。マネージャーが tailwind ビルド後に再現し 0 failures を確認＝実リグレッションではない。
- **判定**: Brakeman リグレッション解消。トピック19の全受け入れ条件（rspec green・カバレッジ85%以上・rubocop クリーン・brakeman リグレッションなし）を満たす。
