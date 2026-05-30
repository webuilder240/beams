# トピック12: ダッシュボード

> `Dashboard` と `Widget` モデルで複数クエリの可視化を縦積み/1〜2カラムグリッドにまとめ、「上へ/下へ」ボタンで並べ替えるダッシュボード機能を実装する。計画書 §4.8 に対応。

- **ステータス**: 未着手
- **依存**: [[11-visualization]]（`Visualization` モデルとチャート描画が完了していること）/ [[03-auth-users]]（`User` モデルと認証が完了していること）
- **関連計画書**: §4.8

## ゴール（完了の定義）

- `Dashboard` モデルと `Widget` モデルが作成され、ダッシュボードにウィジェット（クエリの可視化）を追加・削除できる
- ウィジェットを縦積みまたは 1〜2カラムグリッドで表示できる
- 「上へ/下へ」ボタンで `position` カラムを使い並べ替えができる（ドラッグ&ドロップなし）
- 各ウィジェットに対応するクエリの最新結果が表示される
- Turbo Frames でウィジェット一覧と並べ替えを実装する
- RSpec + System Spec が通り、SimpleCov 85% 以上を維持する

## 前提・参照

- [[11-visualization]] — `Visualization` モデル（`chart_type`, `display_mode`, `x_column`, `y_columns`）
- [[10-query-execution]] — `QueryExecution#result_data`（ウィジェット内の結果表示に使用）
- [[03-auth-users]] — `current_user`、`User` モデル（`owner` 記録用）
- [[07-query-editor]] — `Query` モデル（ウィジェットが参照する）
- 計画書 §4.8: 縦積み or 1〜2カラムグリッド、並べ替えは順序カラム＋「上へ/下へ」、ドラッグ&ドロップなし、自由グリッドは §5 非スコープ
- 計画書 §4.9: ログインユーザーは全ダッシュボードを閲覧・編集可

## タスク

### Dashboard モデル

- [ ] `Dashboard` モデル・マイグレーション作成（`app/models/dashboard.rb`, `db/migrate/YYYYMMDDHHMMSS_create_dashboards.rb`）— カラム: `title:string NOT NULL`, `description:text`, `user_id:references`（所有者。閲覧/編集制限には使わない）, `created_at`, `updated_at`
  - 受け入れ条件: `rails db:migrate` が通る。`Dashboard` が `belongs_to :user` と `has_many :widgets, dependent: :destroy` を持つ
- [ ] `Dashboard` モデルにバリデーション追加（`app/models/dashboard.rb`）— `title` は必須・255文字以内
  - 受け入れ条件: `title` なしで `valid?` が false を返す（RSpec モデルスペックで確認）
- [ ] `Dashboard` の RSpec モデルスペック作成（`spec/models/dashboard_spec.rb`）— バリデーション・アソシエーションをカバー
  - 受け入れ条件: `bundle exec rspec spec/models/dashboard_spec.rb` が全グリーン
- [ ] `Dashboard` の FactoryBot ファクトリ作成（`spec/factories/dashboards.rb`）
  - 受け入れ条件: `create(:dashboard)` が成功する

### Widget モデル

- [ ] `Widget` モデル・マイグレーション作成（`app/models/widget.rb`, `db/migrate/YYYYMMDDHHMMSS_create_widgets.rb`）— カラム: `dashboard_id:references`, `query_id:references`, `position:integer NOT NULL DEFAULT 0`, `column_span:integer NOT NULL DEFAULT 1`（1 or 2、グリッド列幅）, `title_override:string`（空なら Query#title を使う）, `created_at`, `updated_at`
  - 受け入れ条件: `rails db:migrate` が通る。`Widget` が `belongs_to :dashboard` と `belongs_to :query` を持つ
- [ ] `Widget` モデルにバリデーション追加（`app/models/widget.rb`）— `position` は 0以上の整数、`column_span` は 1 or 2 のみ
  - 受け入れ条件: `column_span: 3` で `valid?` が false を返す（RSpec モデルスペックで確認）
- [ ] `Widget` に `display_title` メソッド追加（`app/models/widget.rb`）— `title_override` が空なら `query.title` を返す
  - 受け入れ条件: `title_override` が `nil` のとき `widget.display_title` が `query.title` と等しい（RSpec モデルスペックで確認）
- [ ] `Dashboard` に `ordered_widgets` スコープ追加（`app/models/dashboard.rb`）— `widgets.order(:position)`
  - 受け入れ条件: `dashboard.ordered_widgets` が `position` 昇順で返る（RSpec モデルスペックで確認）
- [ ] `Widget` の RSpec モデルスペック作成（`spec/models/widget_spec.rb`）— バリデーション・アソシエーション・`display_title` をカバー
  - 受け入れ条件: `bundle exec rspec spec/models/widget_spec.rb` が全グリーン
- [ ] `Widget` の FactoryBot ファクトリ作成（`spec/factories/widgets.rb`）
  - 受け入れ条件: `create(:widget)` が成功する

### DashboardsController

- [ ] `DashboardsController` 作成（`app/controllers/dashboards_controller.rb`）— アクション: `index`（一覧）, `show`（詳細）, `new`, `create`, `edit`, `update`, `destroy`。ルート: `resources :dashboards`（`config/routes.rb`）
  - 受け入れ条件: `rails routes` で dashboard の CRUD パスが表示される
- [ ] `index` アクションで全ダッシュボードを `updated_at DESC` 順で取得し一覧表示（`app/controllers/dashboards_controller.rb`, `app/views/dashboards/index.html.erb`）
  - 受け入れ条件: ログイン状態で `/dashboards` にアクセスすると一覧が表示される（System Spec `rack_test` で確認）
- [ ] `create` / `update` アクションで `current_user` を `user_id` に設定（`app/controllers/dashboards_controller.rb`）
  - 受け入れ条件: ダッシュボード作成時に `dashboard.user` が `current_user` と等しい（RSpec リクエストスペックで確認）
- [ ] 未ログイン時に全アクションがログインページにリダイレクトされる（`app/controllers/dashboards_controller.rb`）
  - 受け入れ条件: 未ログイン状態で `GET /dashboards` が 302 を返す（RSpec リクエストスペックで確認）
- [ ] `DashboardsController` の RSpec リクエストスペック作成（`spec/requests/dashboards_spec.rb`）— index/show/create/update/destroy の正常系・未ログイン時リダイレクトをカバー
  - 受け入れ条件: `bundle exec rspec spec/requests/dashboards_spec.rb` が全グリーン

### WidgetsController

- [ ] `WidgetsController` 作成（`app/controllers/widgets_controller.rb`）— アクション: `create`（ウィジェット追加）, `destroy`（ウィジェット削除）, `move_up`, `move_down`（並べ替え）。ルート: `resources :dashboards do; resources :widgets, only: [:create, :destroy] do; member { post :move_up; post :move_down }; end; end`（`config/routes.rb`）
  - 受け入れ条件: `rails routes` で widget の create/destroy/move_up/move_down パスが表示される
- [ ] `create` アクションで新ウィジェットを末尾（現在の最大 `position + 1`）に追加（`app/controllers/widgets_controller.rb`）— Turbo Stream で `<turbo-frame id="widgets">` を更新
  - 受け入れ条件: ウィジェット追加後にページリロードなしでウィジェット一覧に追加される（System Spec `rack_test` で確認）
- [ ] `move_up` / `move_down` アクションで対象ウィジェットと隣接ウィジェットの `position` を入れ替える（`app/controllers/widgets_controller.rb`）— Turbo Stream でウィジェット一覧を再描画
  - 受け入れ条件: 「上へ」ボタンをクリックすると対象ウィジェットが1つ上に移動し、ページリロードなしで反映される（System Spec `rack_test` で確認）
- [ ] `move_up` で先頭ウィジェットの場合は何もしない（`app/models/widget.rb` または `app/controllers/widgets_controller.rb`）
  - 受け入れ条件: 先頭ウィジェットの「上へ」ボタンが非活性または送信しても順序が変わらない（RSpec リクエストスペックで確認）
- [ ] `WidgetsController` の RSpec リクエストスペック作成（`spec/requests/widgets_spec.rb`）— create/destroy/move_up/move_down の正常系と境界ケースをカバー
  - 受け入れ条件: `bundle exec rspec spec/requests/widgets_spec.rb` が全グリーン

### ダッシュボード表示・ウィジェット描画

- [ ] ダッシュボード詳細ビュー作成（`app/views/dashboards/show.html.erb`）— `<turbo-frame id="widgets">` でウィジェット一覧をラップ。各ウィジェットを `_widget.html.erb` パーシャルで描画
  - 受け入れ条件: ダッシュボードにウィジェットが表示される（System Spec `rack_test` で確認）
- [ ] ウィジェットパーシャル作成（`app/views/widgets/_widget.html.erb`）— ウィジェットタイトル・クエリの最新結果（テーブルまたはチャート、`Visualization#display_mode` に従う）・「上へ/下へ」ボタン・削除ボタンを表示。`column_span: 2` のウィジェットは CSS クラスで幅を広げる
  - 受け入れ条件: ウィジェット内にクエリ結果テーブルまたはチャートが表示される（System Spec `rack_test` で確認）
- [ ] 1〜2カラムグリッドレイアウトを CSS で実装（`app/assets/stylesheets/application.css` またはインライン `<style>`）— CSS Grid を使用。`column_span: 1` は `grid-column: span 1`、`column_span: 2` は `grid-column: span 2`
  - 受け入れ条件: `column_span: 2` のウィジェットが他のウィジェットより幅広く表示される（System Spec `rack_test` で確認）
- [ ] ウィジェット追加フォーム（クエリ選択）をダッシュボード詳細ページに追加（`app/views/dashboards/show.html.erb`）— `<select>` でクエリを選び POST する
  - 受け入れ条件: クエリを選んで追加するとウィジェットが一覧に現れる（System Spec `rack_test` で確認）
- [ ] ウィジェット内のチャート描画は Turbo Frame で `show.html.erb`（[[11-visualization]]）をネストして再利用する（`app/views/widgets/_widget.html.erb`）
  - 受け入れ条件: `Visualization#display_mode == "chart"` のウィジェットにチャートが表示される（`js: true` System Spec で確認）

### ダッシュボード CRUD ビュー

- [ ] ダッシュボード一覧ビュー作成（`app/views/dashboards/index.html.erb`）— タイトル・更新日・詳細リンク・編集リンク・削除ボタンを表示
  - 受け入れ条件: ダッシュボードが存在しない場合に「まだダッシュボードがありません」を表示する
- [ ] ダッシュボード新規作成・編集フォームビュー作成（`app/views/dashboards/new.html.erb`, `app/views/dashboards/edit.html.erb`, `app/views/dashboards/_form.html.erb`）— `title` と `description` の入力欄
  - 受け入れ条件: バリデーションエラー時にエラーメッセージが表示される（System Spec `rack_test` で確認）

### System Spec

- [ ] ダッシュボード CRUD の System Spec 作成（`spec/system/dashboards_spec.rb`）— ダッシュボード作成・ウィジェット追加・「上へ/下へ」並べ替え・ウィジェット削除・ダッシュボード削除の一連フローをカバー
  - 受け入れ条件: `bundle exec rspec spec/system/dashboards_spec.rb` が全グリーン（`rack_test` ドライバー）

## 動作確認

- [ ] ダッシュボードを新規作成し、クエリを2つ以上ウィジェットとして追加できる
- [ ] 「上へ」「下へ」ボタンでウィジェットの順序が入れ替わり、リロードしても順序が保持される
- [ ] `column_span: 2` のウィジェットがグリッドで幅広く表示される
- [ ] ダッシュボードを削除するとウィジェットも CASCADE 削除される
- [ ] `bin/rubocop` がエラーなし
- [ ] `bundle exec rspec` がグリーン、SimpleCov 85% 以上

## 未決事項・質問

- ウィジェット内のチャート描画は `<turbo-frame>` で `visualizations#show` をそのまま埋め込む想定だが、パラメータの受け渡し方（`query_id` のみで `visualization` を特定するか）を確認が必要。
- `column_span` の UI（ウィジェット追加時に選択できるか、後から変更できるか）は初期は「追加時に 1 か 2 を選ぶ `<select>`」で実装する想定だが確認が必要。
- ウィジェットが参照するクエリに `QueryExecution` がまだない（未実行）場合の表示をどうするか（「未実行」プレースホルダーを表示する想定）。
