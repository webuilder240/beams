# トピック16: フォームUIのTailwindスタイル統一（不具合修正）

> 複数ページのフォーム入力欄に Tailwind のスタイルが当たっていない不具合を修正し、全フォームの入力欄・ラベル・ボタンのスタイルを共通コンポーネントクラスに統一する。

- **ステータス**: 未着手
- **依存**: [[12-dashboard]]（ダッシュボードフォーム）/ [[11-visualization]]（可視化エディタ）/ [[07-query-editor]]（クエリフォーム）
- **関連計画書**: §3（Beamsリネーム・UI基盤）。機能追加ではなくUI不具合修正。

## 背景・事象

`localhost:3000` で確認したところ、**一部のページのフォーム入力欄に Tailwind のデザインが当たっていない**（枠線が出ない・余白が無く素のブラウザ表示に近い）。

### 根本原因

Tailwind CSS v4 の Preflight（ベースリセット）は全要素に対して以下を適用する（`app/assets/builds/tailwind.css` の `@layer base` 参照）:

```css
*,:after,:before,::backdrop{ box-sizing:border-box; border:0 solid; margin:0; padding:0 }
button,input,select,optgroup,textarea{ ...; background-color:#0000; border-radius:0 }
```

つまり **border-width は既定で 0**。`border-gray-300` は border の**色**だけを指定するユーティリティであり、**`border`（border-width:1px）が併記されていないと枠線は描画されない**。さらに `px-3 py-2`（パディング）が無いフィールドは詰まって見え、素の入力欄のように見える。

正しく表示されているフォーム（例: `app/views/queries/_form.html.erb`, `app/views/sessions/new.html.erb`, `app/views/admin/users/new.html.erb`）はいずれも `class: "w-full rounded border border-gray-300 px-3 py-2"` のように **`border` を併記**している。

### 影響箇所（`border` 併記漏れ）

| ファイル | 対象フィールド | 現在のクラス（不具合） |
|----------|----------------|------------------------|
| `app/views/dashboards/_form.html.erb` | `f.text_field :title` / `f.text_area :description` | `w-full rounded border-gray-300 text-sm`（`border`・padding 無し） |
| `app/views/visualizations/_visualization.html.erb` | `f.select :chart_type` / `:x_column` / `:y_columns` / `:series_column` / `:counter_column` / `:counter_aggregation`（6箇所） | `rounded border-gray-300 text-sm`（`border`・padding・`w-full` 無し） |

> 補足: `app/assets/tailwind/application.css` には既に `.form-input` / `.form-label` / `.btn-primary` / `.btn-secondary` / `.btn-danger` のコンポーネントクラスが定義済みだが、ほとんどのフォームで使われておらず、各ビューがアドホックなクラス文字列を重複記述している。この重複が今回の併記漏れを生んだ温床。

## ゴール（完了の定義）

- 影響箇所のフォーム入力欄に枠線・パディングが正しく描画される（Preflight で枠線が消えない）
- **全フォーム**の入力欄・ラベル・送信ボタンのスタイルが共通コンポーネントクラス（`.form-input` / `.form-label` / `.btn-primary` 等）に統一され、アドホックなクラス文字列の重複が解消される（不具合箇所だけでなく全フォームが対象）
- 入力欄のスタイル付与を検証する RSpec（リグレッションテスト）が green
- 既存テストを壊さず、SimpleCov 85% 以上を維持する
- `bin/rubocop` がエラーなし

## 前提・参照

- Tailwind は `tailwindcss-rails`（v4 系・standalone CLI）。開発時は `bin/dev`（`Procfile.dev` の `css: bin/rails tailwindcss:watch`）でビルドが再生成される。`bin/rails server` 単体では `app/assets/builds/tailwind.css`（コミット済みビルド）が配信されるため、クラス追加後は **ビルド再生成が必要**（`bin/rails tailwindcss:build`）。
- コンポーネントクラス定義: `app/assets/tailwind/application.css` の `@layer components`。
  - `.form-input` … `block w-full rounded-md border border-gray-300 px-3 py-2 text-sm shadow-sm focus:...`
  - `.form-label` … `block text-sm font-medium text-gray-700 mb-1`
  - `.btn-primary` / `.btn-secondary` / `.btn-danger`
- 既存の正しい記述例: `app/views/queries/_form.html.erb`、`app/views/sessions/new.html.erb`。

## タスク

### 1. 共通コンポーネントクラスの確認・拡充

- [ ] `.form-input` / `.form-label` / `.btn-primary` 系が現状の手書きスタイル（`w-full rounded border border-gray-300 px-3 py-2`）と視覚的に等価か確認する（`app/assets/tailwind/application.css`）。差異があれば調整する
  - 受け入れ条件: `.form-input` を当てた入力欄が、既存の正しいフォーム（queries / sessions）と同等の見た目になる
- [ ] `<select multiple>`（`:y_columns`）にも `.form-input` で破綻しないことを確認する。必要なら `min-h` 等を追加
  - 受け入れ条件: 複数選択 select が枠線付きで表示される

### 2. 影響箇所の修正（不具合解消）

- [ ] `app/views/dashboards/_form.html.erb` の `title` / `description` を `.form-input`（＋ラベルを `.form-label`）に置換
  - 受け入れ条件: ダッシュボード新規/編集フォームの入力欄に枠線・パディングが表示される
- [ ] `app/views/visualizations/_visualization.html.erb` の 6 つの `f.select` を `.form-input`（＋ラベルを `.form-label`）に置換
  - 受け入れ条件: 可視化エディタの全 select に枠線が表示される

### 3. 全フォームのスタイル統一（再発防止・本タスクの必須スコープ）

> ユーザー判断により、不具合箇所だけでなく**全フォームをコンポーネントクラスへ統一する**ことを本タスクの確定スコープとする。アドホックなクラス文字列の重複（今回の併記漏れの温床）を一掃する。

対象フォーム（入力欄 → `.form-input`、ラベル → `.form-label`、送信ボタン → `.btn-primary` / 取消・副ボタン → `.btn-secondary`、削除 → `.btn-danger` へ置換）:

- [ ] `app/views/queries/_form.html.erb`（title / bigquery_connection_id / sql_body・submit・キャンセルリンク）
  - 受け入れ条件: 既存の見た目を維持し、入力欄が `.form-input`、ラベルが `.form-label`、送信が `.btn-primary` を使う
- [ ] `app/views/sessions/new.html.erb`（email / password / submit）
- [ ] `app/views/admin/users/new.html.erb`・`app/views/admin/users/edit.html.erb`（email / password / role select / submit）
- [ ] `app/views/admin/settings/edit.html.erb`（number_field / submit）
- [ ] `app/views/bigquery/connections/_form.html.erb`（name / project_id / service_account_json / number_field / submit）
- [ ] `app/views/setup_wizard/step1.html.erb`・`step2.html.erb`・`step4.html.erb`（各入力・submit）
- [ ] `app/views/queries/show.html.erb` 内の実行フォーム・削除ボタン（`submit_tag` / `button_to` を `.btn-*` に）
  - 受け入れ条件（共通）: 各フォームの見た目が劣化せず、入力欄が `.form-input`、ボタンが `.btn-*` を使う。System Spec が全て green のまま
  - 進め方: 一度に全置換せず、**ファイル単位で TDD（下記スペック）→ ビルド再生成 → 目視** を繰り返す。`f.submit` のラベル文字列・フォーム挙動（method / formaction 等）は変更しない（クラスのみ差し替え）

> 注意: ラベル文字列・`name` 属性・送信先・`data-*`（Stimulus ターゲット、turbo_confirm 等）は維持し、**class 属性のみ**を差し替える。これらを変えると既存の System Spec／Stimulus 連携が壊れる。

### 4. ビルド再生成

- [ ] `bin/rails tailwindcss:build` を実行し `app/assets/builds/tailwind.css` を再生成・コミットする（`.form-input` 等が purge されず含まれることを確認）
  - 受け入れ条件: ビルド済み CSS に `.form-input` / `.btn-primary` 等のクラス定義が含まれる

### 5. RSpec（TDD・リグレッション）

- [ ] System Spec（`rack_test`）で、修正対象フォームの入力欄に正しいスタイルフック（`form-input` クラス）が付与されていることを assert（`spec/system/form_styling_spec.rb` 新規）
  - 例: ダッシュボード新規フォームを開き、`expect(page).to have_css("input#dashboard_title.form-input")`、可視化エディタの各 select が `.form-input` を持つこと
  - 受け入れ条件: 先に失敗するスペックを書き（Red）、修正後に green
  - 注記: `rack_test` は CSS を評価しないため、これは「スタイルフックが markup に存在する」ことを担保する構造テスト
- [ ] **（必須・厳密リグレッション／CI 対象）** `js: true`（Playwright）で、入力欄の `getComputedStyle(...).borderTopWidth` が `0px` でないことを検証する CSS リグレッションスペックを 1 本追加（`spec/system/form_styling_spec.rb` に `js: true` example）。対象は不具合箇所（ダッシュボードフォーム入力欄・可視化 select）
  - 受け入れ条件: 修正前は枠線幅 0px で失敗、修正後に枠線幅 > 0 で green。ローカル初回は `npx playwright install chromium` が必要
  - CI: 既存の `system-test` ジョブ（`.github/workflows/ci.yml`）が `npx playwright install chromium --with-deps` 実行後に `bundle exec rspec spec/system` を走らせるため、**`spec/system/` 配下に置けば追加設定なしで CI 対象になる**。`js: true` タグ付けを忘れないこと（CI 変更は原則不要）

## 動作確認

- [ ] `bin/dev` で起動し、以下のページでフォーム入力欄に枠線・余白が表示されることを目視
  - `/dashboards/new`・`/dashboards/:id/edit`
  - `/queries/:id/visualization`（チャート種別・X軸・Y軸・系列・カウンター系の各 select）
  - 既存の `/queries/new`・`/sessions/new`・`/admin/users/new` で見た目が劣化していない
- [ ] `bundle exec rspec` がグリーン、SimpleCov 85% 以上
- [ ] `bin/rubocop` がエラーなし

## 未決事項・質問

- ~~全フォームのコンポーネントクラス統一をスコープに含めるか~~ → **確定: 全フォーム統一を本タスクのスコープとする**（タスク3）。
- ~~`js: true` リグレッションスペックを CI に含めるか~~ → **確定: CI に含める**。`spec/system/` 配下に `js: true` で追加すれば、既存 `system-test` ジョブで自動実行される（ワークフロー変更は不要）。

なし（未決事項は解消済み）。
