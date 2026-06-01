# トピック19 実装ログ: ダッシュボードのドラッグ&ドロップ並び替え

## 実装日時
2026-06-01

## ブランチ
`feat/19-dashboard-drag-drop`

## 実装の流れ（TDD: Red → Green → Refactor）

### Phase 1: Red（テスト先書き）

1. `spec/models/dashboard_spec.rb` に `reorder_widgets!` スペックを追加
   - 並び替え結果検証、position 0始まり確認、他ダッシュボードID無視、部分配列、トランザクション
2. `spec/requests/widgets_spec.rb` の `move_up`/`move_down` スペックを削除し、`PATCH reorder` スペックを追加
   - 正常系（Turbo Stream）、HTMLフォールバック、未ログインリダイレクト、空配列、他ダッシュボードID無視
3. テスト実行確認: 10 failures（Red確認済み）

### Phase 2: Green（実装）

4. **importmap**: `config/importmap.rb` に `sortablejs@1.15.6` を esm.sh 経由で pin
5. **ルート**: `config/routes.rb` から `member { post :move_up/move_down }` を削除し、`collection { patch :reorder }` を追加
6. **モデル**: `Dashboard#reorder_widgets!(ordered_ids)` を追加（自ダッシュボードIDのみ、0始まり連番、トランザクション）
7. **モデル**: `Widget#move_up!/move_down!/swap_with/previous_sibling/next_sibling` を削除
8. **コントローラ**: `WidgetsController#reorder` 追加、`move_up`/`move_down` 削除、`before_action :set_widget` を `:destroy` のみに
9. **ビュー templates**: `reorder.turbo_stream.erb` 新規作成、`move_up/down.turbo_stream.erb` 削除
10. **ビュー**: `_widget.html.erb` から「↑上へ」「↓下へ」ボタン削除、`data-widget-id` 付与、ドラッグハンドル追加
11. **ビュー**: `_widgets.html.erb` に `data-controller="sortable"` と `data-sortable-url-value` 付与
12. **ビュー**: `show.html.erb` にドラッグ操作スタイル追加（sortable-ghost/chosen、drag-handle）
13. **Stimulusコントローラ**: `sortable_controller.js` 新規作成（SortableJS適用、onEnd → PATCH）

### Phase 3: テスト修正・RuboCop対応

14. `spec/models/widget_spec.rb` から `move_up!/move_down!` スペック削除（メソッド削除のため）
15. `spec/system/dashboards_spec.rb`:
    - rack_test の「↓下へ」並び替え検証を削除
    - `js: true` の D&D 並び替え検証を追加（`window.Stimulus.getControllerForElementAndIdentifier`）
    - SortableJS は importmap 経由のため、コントローラロード完了を `sleep 1.0` で待つ必要あり
16. RuboCop: `spec/models/widget_spec.rb` の末尾空行修正
17. `_widgets_stream.turbo_stream.erb` コメント内の参照を更新

## テスト結果

### 非system（spec/models + spec/requests + spec/lib）
```
411 examples, 0 failures
Line Coverage: 92.08% (872 / 947)
```

### system（spec/system/dashboards_spec.rb）
```
9 examples, 0 failures
```

## RuboCop
```
145 files inspected, no offenses detected
```

## コミット一覧

| ハッシュ | 内容 |
|---------|------|
| `254475a` | feat(importmap+js): SortableJS導入とsortable Stimulusコントローラ追加 |
| `a823e05` | feat(routes+models): move_up/move_down廃止、reorderルートとDashboard#reorder_widgets!追加 |
| `af14d56` | feat(controller): WidgetsController#reorderアクション追加とmove_up/move_down削除 |
| `d099fdc` | feat(views): 上へ/下へボタン削除、ドラッグハンドル追加、sortableコントローラ適用 |
| `bae32f1` | test(system): rack_testの「下へ」並び替え検証をPlaywright D&Dへ置き換え |
| `5243fa5` | test(system+spec): D&DシステムスペックをPlaywright経由で確立、RuboCop修正 |

## PlaywrightのD&D発火について

SortableJSはPointerEventsを使用するため、`page.driver.browser.mouse.move/down/up` は
Capybara::Playwright::Driverではprivateメソッドとして呼び出せない（`NoMethodError`）。

また、`drag_to` や素のPointerEventディスパッチも単独では発火しなかった。

最終的に採用した方法：
1. Stimulusコントローラのロード完了を `sleep 1.0` で待つ
2. `page.execute_script` で DOM の子要素順を変更
3. `window.Stimulus.getControllerForElementAndIdentifier(grid, 'sortable')` でコントローラ取得
4. `ctrl.onEnd()` を直接呼び出し、reorderエンドポイントへのfetchを発火

これにより実際のサーバーへのPATCHリクエストとpositionの永続化が確認できる。

## 追加対応: 保存失敗時のUX（2026-06-01）

### 実装内容

1. **トースト通知機構を新設** (`app/javascript/controllers/toast_controller.js`)
   - `window.addEventListener("toast:show", ...)` でカスタムイベントを購読
   - `type: "error"` → `bg-red-50 border-red-200 text-red-700` の赤系スタイル
   - `type: "notice"` → 緑系スタイル
   - `AUTO_DISMISS_MS = 4000` ミリ秒後に自動消滅、手動クローズボタン付き
   - `app/views/layouts/application.html.erb` に `fixed bottom-4 right-4` の固定コンテナを追加

2. **`sortable_controller.js` の失敗ハンドリング拡張**
   - `onEnd` 送信前に `currentChildren`（ドラッグ後DOM順）と `originalChildren`（復元用元順序）を保持
   - `oldIndex`/`newIndex` を逆算して元の順序を再現
   - `response.ok` false または `.catch` で `_restoreOrder(originalChildren)` を呼びDOMを復元
   - 復元後に `toast:show` (type: error) を発火

3. **System Spec追加** (`spec/system/dashboards_spec.rb`)
   - `toast notification` describe: `toast:show` 発火→右下表示→自動消滅を検証 (js: true)
   - `widget drag-and-drop reorder failure` describe: `pw.route` で500インターセプト→ドラッグ→トースト表示＋DOM復元＋サーバ状態不変を検証 (js: true)

### テスト結果（追加対応後）

#### System Spec（3回連続）
```
11 examples, 0 failures  # 3回とも
```

#### 非system フルスイート
```
433 examples, 0 failures
Line Coverage: 98.67% (964 / 977)
```

#### RuboCop
```
145 files inspected, no offenses detected
```

### コミット一覧（追加対応）

| ハッシュ | 内容 |
|---------|------|
| `b355495` | test(system): 保存失敗時のUX検証 System Spec 追加（toast通知・DOM復元・サーバ状態不変） |
| `12f8da7` | feat(toast): 汎用トースト通知機構を新設（toast_controller.js + レイアウト固定コンテナ） |
| `01dab58` | feat(sortable): reorder失敗時のDOM復元とトースト通知を追加 |
| `58f569c` | docs(progress): トピック19追加対応のチェックボックスを完了化し進捗ログを更新 |

## Brakeman SQL Injection 修正（2026-06-01）

### 問題
`reorder_widgets!` の `update_all(["position = #{case_sql}", ...])` にて Brakeman が
SQL Injection（Confidence: Weak）を検知。CI の `scan_ruby` が赤になるリグレッション。

### 対応（コードで解決、ignore 未使用）

- `Widget.update(filtered, attrs)` に書き換え（生SQL文字列補間を排除）。
  - `attrs` は `filtered.each_with_index.map { |_id, index| { position: index } }` で生成。
  - `transaction` ブロックで囲み、契約不変を維持。
  - ウィジェット数は実運用で少数のため複数 UPDATE でも問題なし。

### 検証結果

#### Brakeman
```
Security Warnings: 0  (SQL Injection 警告 消滅)
```

#### spec/models/dashboard_spec.rb
```
19 examples, 0 failures
```

#### RuboCop
```
145 files inspected, no offenses detected
```

#### spec/models（全体）
```
224 examples, 0 failures
```

### コミット

| ハッシュ | 内容 |
|---------|------|
| `007d02d` | fix(models): reorder_widgets! をWidget.updateイディオムに書き換えBrakeman警告を解消 |
