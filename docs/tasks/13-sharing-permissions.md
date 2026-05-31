# トピック13: 共有・権限（組織フルオープン）

> ログインユーザーは全クエリ・全ダッシュボードを閲覧・編集可とし、所有者は記録するが制限を設けない「組織フルオープン」ポリシーをアプリ全体に適用する。計画書 §4.9 に対応。

- **ステータス**: ✅完了
- **依存**: [[03-auth-users]]（`User` モデルと認証が完了していること）/ [[07-query-editor]]（`Query` モデルが存在すること）/ [[12-dashboard]]（`Dashboard` モデルが存在すること）
- **関連計画書**: §4.9

## ゴール（完了の定義）

- ログイン済みユーザーは他ユーザーが作成したクエリ・ダッシュボードを閲覧・編集・削除できる
- 未ログインユーザーはすべてのリソースにアクセスできず、ログインページにリダイレクトされる
- `Query` と `Dashboard` に `user_id`（所有者）カラムが存在し、作成時に `current_user` が記録される
- 所有者による閲覧・編集制限のためのロール/権限チェックコードが存在しない
- グループ/ロール権限・公開リンクは実装しない
- RSpec が通り、SimpleCov 85% 以上を維持する

## 前提・参照

- [[03-auth-users]] — `current_user` ヘルパー、`before_action :require_login`（またはそれに相当する認証フィルタ）
- [[07-query-editor]] — `Query` モデル（`user_id` カラムが必要、なければ追加マイグレーション）
- [[12-dashboard]] — `Dashboard` モデル（`user_id` カラムは [[12-dashboard]] で追加済み）
- 計画書 §4.9: 所有者は記録するが閲覧・編集制限なし。細かい権限モデルは作らない
- 計画書 §5 非スコープ: グループ/ロール権限、公開リンク（ログイン不要）

## タスク

### 認証フィルタの適用確認

- [ ] `ApplicationController` に `before_action :require_login`（またはそれに相当するメソッド）が設定されており、全コントローラでデフォルト適用されることを確認・修正する（`app/controllers/application_controller.rb`）
  - 受け入れ条件: 未ログイン状態で `GET /queries` にアクセスすると 302 でログインページにリダイレクトされる（RSpec リクエストスペックで確認）

### Query への user_id 記録

- [ ] `Query` モデルに `user_id` カラムが存在しない場合は追加マイグレーションを作成する（`db/migrate/YYYYMMDDHHMMSS_add_user_id_to_queries.rb`）— `add_reference :queries, :user, null: true, foreign_key: true`（既存レコードへの対応で `null: true`）
  - 受け入れ条件: `rails db:migrate` が通る。`Query` が `belongs_to :user, optional: true` を持つ
- [ ] `QueriesController#create` と `#update` で `current_user` を `query.user` に設定する（`app/controllers/queries_controller.rb`）
  - 受け入れ条件: クエリ作成時に `query.user_id` が `current_user.id` と等しい（RSpec リクエストスペックで確認）
- [ ] クエリ一覧・詳細画面でオーナー名（`query.user.email` 等）を表示する（`app/views/queries/index.html.erb`, `app/views/queries/show.html.erb`）— 表示のみ、制限なし
  - 受け入れ条件: 一覧ページにオーナー名カラムが表示される（System Spec `rack_test` で確認）

### Dashboard への user_id 記録確認

- [ ] [[12-dashboard]] で `Dashboard` に `user_id` が設定済みであることを確認し、`DashboardsController#create` で `current_user` を設定している（`app/controllers/dashboards_controller.rb`）— [[12-dashboard]] で実装済みであればこのタスクは確認のみ
  - 受け入れ条件: ダッシュボード作成時に `dashboard.user_id` が `current_user.id` と等しい（RSpec リクエストスペックで確認）

### 権限チェックを持たないことの明示

- [ ] `QueriesController` と `DashboardsController` に `authorize!` / `policy_scope` 等の権限チェックコードが存在しないことを確認する（Pundit, CanCanCan 等を導入しない）（`app/controllers/queries_controller.rb`, `app/controllers/dashboards_controller.rb`）
  - 受け入れ条件: ユーザーAが作成したクエリをユーザーBが編集・削除できる（RSpec リクエストスペックで確認）

### RSpec

- [ ] 共有ポリシーの RSpec リクエストスペック追加（`spec/requests/sharing_spec.rb` または既存スペックに追記）— 「ユーザーAが作成したリソースをユーザーBが閲覧・編集できる」ケースを Query と Dashboard それぞれでカバー
  - 受け入れ条件: `bundle exec rspec spec/requests/sharing_spec.rb` が全グリーン

## 動作確認

- [ ] ユーザーAでログインしてクエリを作成し、ユーザーBでログインしてそのクエリを編集・削除できる
- [ ] 未ログイン状態で `/queries` にアクセスするとログインページにリダイレクトされる
- [ ] `bin/rubocop` がエラーなし
- [ ] `bundle exec rspec` がグリーン、SimpleCov 85% 以上

## 未決事項・質問

なし
