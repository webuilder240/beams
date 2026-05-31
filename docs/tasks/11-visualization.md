# トピック11: 可視化（Chart.js）

> クエリ結果をChart.jsで折れ線・棒・円・面・散布図に描画し、テーブル⇄チャート切替・軸設定・CSVエクスポートを提供する。計画書 §4.7 に対応。

- **ステータス**: ✅完了（Tester PASS）
- **依存**: [[10-query-execution]]（`QueryExecution` と結果blob取得が完了していること）/ [[03-auth-users]]（`User` モデルと認証が完了していること）
- **関連計画書**: §4.7

## ゴール（完了の定義）

- `config/importmap.rb` に Chart.js がピン留めされ、importmap 経由でブラウザに配信される
- `Visualization` モデルで X軸カラム・Y軸カラム・系列カラム・チャート種別（chart_type）・表示モード（table/chart）を保存できる
- クエリ結果画面でテーブル表示とチャート表示を切り替えられる
- Stimulus コントローラが Chart.js を呼び出して折れ線・棒・円・面・散布図を描画できる
- X軸・Y軸・系列をドロップダウンUIで指定でき、設定を保存・復元できる
- CSVエクスポートが X-Sendfile 経由でダウンロードできる
- RSpec + System Spec が通り、SimpleCov 85% 以上を維持する

## 前提・参照

- [[10-query-execution]] — `QueryExecution#result_data`（圧縮blob展開後の列スキーマ＋行配列）を参照する
- [[03-auth-users]] — `current_user` セッションヘルパー
- [[07-query-editor]] — `Query` モデル（`has_one :visualization` の関連先）
- 計画書 §4.7: Chart.js（importmap）+ Stimulus で描画。CSVは X-Sendfile で配信
- 計画書 §3: Puma + Thruster が X-Sendfile を処理する
- Chart.js 公式 CDN URL（またはベンダーファイル）: https://cdn.jsdelivr.net/npm/chart.js
- `config/importmap.rb` — 現在 Hotwire のみピン留め（[[01-foundation-rename]] 後）
- Thruster の X-Sendfile ヘッダ設定: `response.headers["X-Sendfile"]` + `send_file` の代替として `X-Accel-Redirect`

## タスク

### Chart.js importmap ピン留め

- [x] Chart.js を CDN pin で `config/importmap.rb` にピン留めする（`config/importmap.rb`）— `bin/importmap pin chart.js` を実行し、生成された CDN pin（`pin "chart.js", to: "https://..."` 形式）を確認する。vendored ファイルは使用しない
  - 受け入れ条件: `config/importmap.rb` に chart.js の CDN pin が追加され、`js: true` System Spec でチャートが描画される

### Visualization モデル

- [x] `Visualization` モデル・マイグレーション作成（`app/models/visualization.rb`, `db/migrate/YYYYMMDDHHMMSS_create_visualizations.rb`）— カラム: `query_id:references`, `chart_type:string`（`"line"/"bar"/"pie"/"area"/"scatter"`, default: `"line"`）, `x_column:string`, `y_columns:string`（JSON配列をtext保存）, `series_column:string`, `display_mode:string`（`"table"/"chart"`, default: `"table"`）, `created_at`, `updated_at`
  - 受け入れ条件: `rails db:migrate` が通る。`Visualization` が `belongs_to :query` を持ち、`Query` が `has_one :visualization, dependent: :destroy` を持つ
- [x] `Visualization` モデルにバリデーション追加（`app/models/visualization.rb`）— `chart_type` は許可リスト（`line/bar/pie/area/scatter`）、`display_mode` は `table/chart` のみ
  - 受け入れ条件: 不正な `chart_type` を渡すと `valid?` が false を返す（RSpec モデルスペックで確認）
- [x] `y_columns` の JSON シリアライズヘルパー追加（`app/models/visualization.rb`）— `store_accessor` または `serialize` で文字列配列として透過的に扱えるようにする
  - 受け入れ条件: `visualization.y_columns = ["col_a", "col_b"]` を保存・再取得すると `Array` が返る（RSpec モデルスペックで確認）
- [x] `Visualization` の RSpec モデルスペック作成（`spec/models/visualization_spec.rb`）— バリデーション・アソシエーション・y_columns シリアライズをカバー
  - 受け入れ条件: `bundle exec rspec spec/models/visualization_spec.rb` が全グリーン

### VisualizationsController

- [x] `VisualizationsController` 作成（`app/controllers/visualizations_controller.rb`）— アクション: `show`（チャート設定フォームと結果表示）, `update`（設定保存）。ルート: `resources :queries do; resource :visualization, only: [:show, :update]; end`（`config/routes.rb`）
  - 受け入れ条件: `rails routes` で `query_visualization` パスが表示される
- [x] `update` アクションで `Visualization` をupsertし、設定変更後にチャートを再描画する（`app/controllers/visualizations_controller.rb`）— Turbo Frame でフォームと描画エリアをまとめてリフレッシュ
  - 受け入れ条件: フォーム送信後にリダイレクトなしでチャートが更新される（System Spec `rack_test` で確認）
- [x] `VisualizationsController` の RSpec リクエストスペック作成（`spec/requests/visualizations_spec.rb`）— 未ログイン時のリダイレクト、ログイン時の show/update 正常系をカバー
  - 受け入れ条件: `bundle exec rspec spec/requests/visualizations_spec.rb` が全グリーン

### テーブル⇄チャート切替 UI

- [x] クエリ結果ページにテーブル/チャート切替タブを追加（`app/views/visualizations/show.html.erb`）— Turbo Frame でラップし、モード切替時に `display_mode` を `update` へ Turbo Form で送信する
  - 受け入れ条件: ブラウザでタブをクリックするとテーブル/チャートエリアが切り替わる（System Spec `rack_test` で確認）
- [x] テーブル表示パーシャル作成（`app/views/visualizations/_result_table.html.erb`）— `QueryExecution#result_data` から列ヘッダ＋行をHTML `<table>` でレンダリング
  - 受け入れ条件: 結果が空のとき「データなし」を表示する（RSpec ビュースペックまたは System Spec で確認）

### 軸設定 UI

- [x] X軸・Y軸・系列カラム指定ドロップダウンを `show` ビューに追加（`app/views/visualizations/show.html.erb`）— 結果の列名一覧を `<select>` に展開し、`visualization` の現在値を初期選択状態にする
  - 受け入れ条件: 列名が正しく選択肢に並ぶ（System Spec `rack_test` で確認）
- [x] チャート種別（折れ線・棒・円・面・散布図）選択ラジオボタンまたは `<select>` を追加（`app/views/visualizations/show.html.erb`）
  - 受け入れ条件: 選択後に保存すると `visualization.chart_type` が更新される（System Spec `rack_test` で確認）

### Stimulus チャートコントローラ

- [x] `chart_controller.js` を Stimulus コントローラとして作成（`app/javascript/controllers/chart_controller.js`）— `connect()` で `data-chart-config-value`（JSON）を読み、Chart.js インスタンスを生成する。`values` API で設定変更時に `disconnect()` → 再描画
  - 受け入れ条件: `js: true` System Spec でチャートキャンバスが DOM に存在し、`<canvas>` タグが描画される
- [x] `show.html.erb` のチャートエリアに `data-controller="chart"` と `data-chart-config-value` を埋め込む（`app/views/visualizations/show.html.erb`）— サーバーサイドで `result_data` から Chart.js `data` オブジェクトを組み立て JSON として渡す
  - 受け入れ条件: `js: true` System Spec で折れ線・棒・円・面・散布図がそれぞれ描画エラーなし
- [x] `chart_type: "area"` のとき Chart.js の `type: "line"` ＋ `fill: true` で面グラフを描画するヘルパーメソッドを追加（`app/helpers/visualization_helper.rb` または `app/javascript/controllers/chart_controller.js` 内）
  - 受け入れ条件: `chart_type = "area"` を保存してチャートページを開くと面グラフが表示される（`js: true` System Spec で確認）
- [x] `chart_controller.js` の Stimulus Unit テストまたは `js: true` System Spec を作成（`spec/system/visualizations_spec.rb`）— 折れ線・棒・円 3種の描画と切替を最低限カバー
  - 受け入れ条件: `bundle exec rspec spec/system/visualizations_spec.rb` が全グリーン（`npx playwright install chromium` 済み環境で実行）

### CSVエクスポート

- [x] 結果画面に「CSVダウンロード」リンクを追加（`app/views/visualizations/show.html.erb`）— [[10-query-execution]] で実行時に `/storage` へ保存済みの全件CSV を X-Sendfile 配信するエンドポイント（`QueryExecutionsController` 側）へリンクする。可視化側では CSV を独自に生成しない
  - 受け入れ条件: リンクをクリックすると [[10-query-execution]] のダウンロード経路経由で CSV ダウンロードが始まる（System Spec `rack_test` で確認）

## 動作確認

- [ ] `bin/rails server` 起動後、クエリ実行済み状態でクエリ詳細ページを開き「チャート」タブに切り替えると折れ線グラフが表示される（実機・Tester/人間確認）
- [ ] X軸・Y軸を変更して保存し、ページをリロードしても設定が保持されている（実機・Tester/人間確認）
- [ ] チャート種別を「円」に切り替えると正しくパイチャートが表示される（実機・Tester/人間確認）
- [ ] 「CSVダウンロード」リンクをクリックするとCSVファイルがダウンロードされ、列名と行が正しい（実機・Tester/人間確認）
- [x] `bin/rubocop` がエラーなし
- [x] `bundle exec rspec` がグリーン、SimpleCov 85% 以上

## 未決事項・質問

- `y_columns`（複数Y軸）のUIはどの程度複雑にするか。複数選択 `<select multiple>` か、チェックボックスリストか。初期は `select multiple` で実装する想定だが確認が必要。
- ✅決定: CDN pinで確定（2026-05-31）。`bin/importmap pin chart.js` で取得した CDN pin を使用する。将来オフライン要件時はvendoring余地あり。
- ✅決定: 全件CSVは[[10-query-execution]]の責務。可視化はリンクのみ。
