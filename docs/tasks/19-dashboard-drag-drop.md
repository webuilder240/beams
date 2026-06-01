# トピック19: ダッシュボードのドラッグ&ドロップ並び替え

> ダッシュボード詳細のウィジェットグリッドを、ドラッグ&ドロップで並び替えできるようにする。
> 技術要件は **Hotwire スタック（Turbo + Stimulus + importmap）** で実現し、Vue/React 等のリアクティブライブラリは使わない。
> D&D の操作には **SortableJS** を importmap 経由で導入し、Stimulus コントローラでラップする。

- **ステータス**: ✅完了
- **依存**: [[12-dashboard]]（`Dashboard` / `Widget` / `position` カラム / グリッド表示が完了していること）
- **関連計画書**: §4.8（並べ替え。元はD&Dなしだったが、本トピックでD&Dへ拡張する）

## ユーザー決定事項（着手前にボス確認済み）

1. **D&D 実現方式**: SortableJS を importmap に pin（CDN: esm.sh、既存の Chart.js / CodeMirror と同方針）し、Stimulus コントローラでグリッドに適用する。
2. **既存「上へ/下へ」ボタンは D&D に置き換える**（ボタンは削除）。→ 並び替えは **JS 必須**になる。並び替えの System Spec は `rack_test` では書けないため `js: true`（Playwright）へ移す。
3. **永続化は一括並び替えエンドポイントを新設**: `PATCH /dashboards/:dashboard_id/widgets/reorder` が widget ID の順序配列を受け取り、`position` を一括更新する（中間結果を 1 リクエストで保存）。

## ゴール（完了の定義）

- ダッシュボード詳細でウィジェットをドラッグ&ドロップして並び替えできる
- D&D で確定した順序が `position` に永続化され、リロード後も保持される
- 既存の「上へ/下へ」ボタン・`move_up`/`move_down` ルート/アクション/モデルメソッドは削除されている
- リアクティブライブラリ（Vue/React 等）を使っていない（importmap + Stimulus + SortableJS のみ）
- RSpec（モデル/リクエスト）green、並び替えの System Spec（`js: true`）green、SimpleCov 85% 以上、`bin/rubocop` クリーン

## 前提・参照（実読済みの現状）

- `app/models/widget.rb` — `position`（integer, NOT NULL, default 0）、`column_span`(1/2)。現状 `move_up!`/`move_down!`/`swap_with`（→ 削除対象）。
- `app/models/dashboard.rb` — `has_many :widgets, dependent: :destroy`、`ordered_widgets`（`widgets.order(:position)`）。
- `app/controllers/widgets_controller.rb` — `create`/`destroy`/`move_up`/`move_down`、`respond_with_widgets`（`<turbo-frame id="widgets">` を再描画）。
- `config/routes.rb` — `resources :dashboards do resources :widgets, only: [:create,:destroy] do member { post :move_up; post :move_down } end end`。
- ビュー: `app/views/dashboards/show.html.erb`（`.dashboard-grid` CSS Grid、`turbo_frame_tag "widgets"`）、`app/views/widgets/_widgets.html.erb`（グリッドコンテナ）、`app/views/widgets/_widget.html.erb`（「上へ/下へ/削除」ボタン）。
- JS: `config/importmap.rb`（Stimulus + turbo-rails、Chart.js/CodeMirror は esm.sh pin）、`app/javascript/controllers/`（`index.js` で自動登録）。
- **マイグレーション不要**: `position` カラムは既存。新規 DB 変更なし。

## タスク

### SortableJS 導入（importmap）

- [x] `config/importmap.rb` に SortableJS を pin（`pin "sortablejs", to: "https://esm.sh/sortablejs@1.15.6"` 等、esm.sh の安定版）
  - 受け入れ条件: `bin/importmap json`（または起動）で `sortablejs` が解決される。既存 pin を壊さない。

### Stimulus コントローラ（D&D + 永続化呼び出し）

- [x] `app/javascript/controllers/sortable_controller.js` を新規作成 — SortableJS をグリッド要素に適用。各ウィジェット要素は `data-widget-id` を持つ。ドロップ確定（`onEnd`）時に現在の DOM 順から widget ID 配列を集め、`reorder` エンドポイントへ `PATCH`（CSRF トークン付与、`Turbo` または `fetch` で送信）する。
  - 値（values）: `url`（reorder のパス）。targets はグリッド自身（コントローラを root に付与）。
  - 受け入れ条件: コントローラが Stimulus に自動登録され、グリッドで D&D ハンドルが機能する（System Spec `js: true` で確認）。
- [x] 送信は Hotwire 流儀で行う（`Turbo.fetch` か標準 `fetch` + `X-CSRF-Token` ヘッダ、`Accept: text/vnd.turbo-stream.html`）。リアクティブライブラリは使わない。
  - 受け入れ条件: D&D 後にサーバの `position` が更新される（System Spec で `dashboard.reload.ordered_widgets` を検証）。

### ルート

- [x] `config/routes.rb` — `member { post :move_up; post :move_down }` を削除し、widgets コレクションに `collection { patch :reorder }` を追加（`PATCH /dashboards/:dashboard_id/widgets/reorder`、`reorder_dashboard_widgets_path`）。
  - 受け入れ条件: `bin/rails routes | grep widgets` に `reorder` が出て、`move_up`/`move_down` が消えている。

### モデル（一括並び替えロジック／service クラス禁止）

- [x] `Dashboard#reorder_widgets!(ordered_ids)` を追加（`app/models/dashboard.rb`）— 渡された widget ID 配列の順に `position` を 0,1,2,… で一括更新。**そのダッシュボードに属する ID のみ**を対象にし、配列に無い既存ウィジェットや他ダッシュボードの ID は無視/除外する。トランザクションで実行。
  - 受け入れ条件: `dashboard.reorder_widgets!([w3.id, w1.id, w2.id])` 後に `ordered_widgets` が `[w3, w1, w2]` 順（RSpec モデルスペック）。他ダッシュボードの ID を混ぜても無視される。
- [x] `Widget#move_up!`/`move_down!`/`swap_with`/`previous_sibling`/`next_sibling` を削除（D&D に置き換えるため）。
  - 受け入れ条件: 当該メソッドが `widget.rb` から消えている。`grep -rn "move_up\|move_down\|swap_with" app/` がヒットしない。

### コントローラ

- [x] `WidgetsController#reorder` を追加し、`move_up`/`move_down` アクションを削除（`app/controllers/widgets_controller.rb`）。`reorder` は `params[:widget_ids]`（配列）を受け、`@dashboard.reorder_widgets!(params[:widget_ids])` を呼ぶ。応答は Turbo Stream で `<turbo-frame id="widgets">` を再描画、HTML フォールバックは詳細へリダイレクト（または `head :ok`）。
  - 受け入れ条件: `PATCH reorder` に順序配列を送ると `position` が更新され、Turbo Stream 応答が返る（RSpec リクエストスペック）。
- [x] `before_action :set_widget` の対象から `move_up`/`move_down` を外す（reorder は単一 widget を取らない）。
  - 受け入れ条件: reorder で `set_widget` が走らない（`params[:id]` を要求しない）。

### ビュー

- [x] `app/views/widgets/_widget.html.erb` — 「↑ 上へ」「↓ 下へ」ボタンを削除し、ドラッグハンドル（例: `⠿` アイコン、`cursor: move`）を追加。`<article>` に `data-widget-id="<%= widget.id %>"` を付与。削除ボタンは残す。
  - 受け入れ条件: ウィジェットに上へ/下へボタンが無く、ドラッグハンドルがある。
- [x] `app/views/widgets/_widgets.html.erb` — `.dashboard-grid` に Stimulus コントローラ（`data-controller="sortable"`、`data-sortable-url-value="<%= reorder_dashboard_widgets_path(dashboard) %>"`）を付与。
  - 受け入れ条件: グリッドに `data-controller="sortable"` が付き、reorder URL が値として渡る。
- [x] D&D 操作領域・ハンドルの最小スタイル（`show.html.erb` の `<style>` か Tailwind クラス）。ドラッグ中のプレースホルダ表示は SortableJS のクラスに任せる。
  - 受け入れ条件: ハンドルが視認でき、D&D 操作ができる。

### テスト

- [x] `spec/models/dashboard_spec.rb` に `reorder_widgets!` のスペックを追加 — 並び替え結果、他ダッシュボード ID の無視、対象外 ID の扱い。
  - 受け入れ条件: `bundle exec rspec spec/models/dashboard_spec.rb` green。
- [x] `spec/requests/widgets_spec.rb` — `move_up`/`move_down` のスペックを削除し、`PATCH reorder` のスペックを追加（正常系・未ログインリダイレクト・不正/欠落パラメータの境界）。
  - 受け入れ条件: `bundle exec rspec spec/requests/widgets_spec.rb` green。
- [x] `spec/system/dashboards_spec.rb` — `rack_test` の「↓ 下へ」並び替え検証ブロックを、`js: true`（Playwright）の D&D 並び替え検証に置き換える。CRUD/追加/削除の他の rack_test は維持（並び替え部分のみ切り出して js:true 化）。
  - 受け入れ条件: `bundle exec rspec spec/system/dashboards_spec.rb` green（並び替えは Playwright で実 D&D を行い、`dashboard.reload.ordered_widgets` の順序が変わることを検証）。

## 動作確認

- [ ] ダッシュボードにウィジェットを2つ以上追加し、ドラッグ&ドロップで順序を入れ替えられる
- [ ] 入れ替え後にリロードしても順序が保持される（`position` 永続化）
- [ ] 「上へ/下へ」ボタンが無くなっている
- [ ] `column_span: 2` のグリッド表示は従来どおり維持される
- [ ] `bin/rubocop` エラーなし、`bundle exec rspec` green、SimpleCov 85% 以上
- [ ] `bin/brakeman` でリグレッションが出ない（reorder の mass-update 周り）

## 追加対応: 保存失敗時のUX（フォローアップ、ボス承認済み 2026-06-01）

> D&D の保存（`PATCH reorder`）は即時実行されるが、失敗時（4xx/5xx・ネットワークエラー・CSRF欠落）は現状 `console.error` のみで、画面の並び順とサーバ状態が無音でズレる。これを解消する。
> **ボス決定**: 失敗時は (1) **並び順を元（ドラッグ前＝サーバの状態）に戻す**、(2) **画面右下のトースト**でエラー通知する。トーストは**汎用機構として新設**（他機能でも再利用可能に）。

- [x] **トースト通知機構を新設**（`app/javascript/controllers/toast_controller.js` ＋ レイアウトに固定コンテナ）— 画面右下に固定表示、一定時間後に自動消滅（手動クローズも可）。`type`（error/notice 等）でスタイル切替。既存の赤系アラート配色（`bg-red-50 border-red-200 text-red-700`）と調和させる。Stimulus の流儀で、カスタムイベント（例: `window.dispatchEvent(new CustomEvent("toast:show", { detail: { message, type } }))`）を購読して表示する再利用可能な作りにする。
  - 受け入れ条件: 任意の箇所から `toast:show` イベントを発火するとトーストが右下に表示され、数秒後に消える（System Spec `js: true` で確認）。
- [x] **`sortable_controller.js` の失敗ハンドリングを拡張**（`app/javascript/controllers/sortable_controller.js`）— `onEnd` で送信前に現在の並び順（widget 要素列）を保持し、`fetch` の `.catch`（および `response.ok` false）時に **DOM をドラッグ前の順序へ復元**してから、`toast:show` を error で発火する。成功時の挙動（Turbo Stream 再描画）は不変。
  - 受け入れ条件: reorder が失敗すると、グリッドの並びがドラッグ前に戻り、右下にエラートーストが出る。サーバの `position` は変化しない。
- [x] **System Spec（`js: true`）追加**（`spec/system/dashboards_spec.rb`）— Playwright のリクエストインターセプト（`page.driver.with_playwright_page { |pw| pw.route("**/widgets/reorder", ...) }` で 500 応答を返す等）で reorder を失敗させ、(a) エラートーストが表示される、(b) 並び順がドラッグ前に戻る、(c) `dashboard.reload.ordered_widgets` の順序が変わっていない、を検証する。
  - 受け入れ条件: 当該 System Spec が green（実ドラッグ→強制失敗→復元＆トーストを検証）。
- [x] 既存テスト（成功系の D&D・モデル・リクエスト）が引き続き green、SimpleCov 85% 以上、`bin/rubocop` クリーン。

## 未決事項・質問

- SortableJS のバージョンは esm.sh の安定版（1.15 系）を想定。pin が解決できない場合は Coder がマネージャーに相談。
- reorder の応答は Turbo Stream 再描画（順序サーバ確定）とするか、`head :ok`（クライアント DOM を信頼）とするか。初期実装は **Turbo Stream で再描画**（サーバを正とする）を想定。
- Playwright での D&D は SortableJS が HTML5 ネイティブ DnD ではなくポインタイベントを使うため、`capybara` の `drag_to` だけでは発火しないことがある。発火しない場合は Playwright の手動ポインタ操作（マウスダウン→移動→アップ）で代替する。
