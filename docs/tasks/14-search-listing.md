# トピック14: 探しやすさ・一覧検索

> クエリとダッシュボードを更新日順で一覧表示し、タイトルの部分一致検索のみを提供するシンプルな探索機能を実装する。計画書 §4.11 に対応。

- **ステータス**: ✅完了
- **依存**: [[07-query-editor]]（`Query` モデルが存在すること）/ [[12-dashboard]]（`Dashboard` モデルが存在すること）/ [[03-auth-users]]（認証が完了していること）
- **関連計画書**: §4.11

## ゴール（完了の定義）

- クエリ一覧がデフォルトで `updated_at DESC` 順に表示される
- ダッシュボード一覧がデフォルトで `updated_at DESC` 順に表示される
- タイトルの部分一致（`LIKE %keyword%`）で絞り込める検索フォームが各一覧ページに存在する
- 検索キーワードなしの場合は全件を返す
- タグ・お気に入り・SQL全文検索は実装しない
- RSpec が通り、SimpleCov 85% 以上を維持する

## 前提・参照

- [[07-query-editor]] — `Query` モデル（`title:string`, `updated_at`）
- [[12-dashboard]] — `Dashboard` モデル（`title:string`, `updated_at`）
- [[03-auth-users]] — `before_action :require_login` が全コントローラに適用済み
- 計画書 §4.11: 更新日順一覧＋タイトル部分一致検索のみ。タグ・お気に入り・SQL全文検索は将来（§7）
- SQLite の `LIKE` は大文字小文字を区別しない（ASCII範囲）ため、追加の処理は不要

## タスク

### Query 一覧・検索

- [ ] `QueriesController#index` で `updated_at DESC` 順取得・タイトル部分一致検索を実装（`app/controllers/queries_controller.rb`）— `params[:q]` が存在する場合に `where("title LIKE ?", "%#{sanitized_q}%")` で絞り込む。`sanitized_q` は `params[:q].to_s.strip`
  - 受け入れ条件: `GET /queries?q=foo` でタイトルに "foo" を含むクエリのみが返る（RSpec リクエストスペックで確認）
- [ ] クエリ一覧ビューに検索フォームを追加（`app/views/queries/index.html.erb`）— `<form method="get">` で `q` パラメータを送信するテキスト入力と送信ボタン。検索後もキーワードが入力欄に残る
  - 受け入れ条件: 検索フォームに入力して送信すると絞り込まれた一覧が表示される（System Spec `rack_test` で確認）
- [ ] クエリ一覧に更新日時カラムを表示する（`app/views/queries/index.html.erb`）— `updated_at` を `l(query.updated_at, format: :short)` 等でフォーマット
  - 受け入れ条件: 一覧に更新日時が表示される（System Spec `rack_test` で確認）
- [ ] `Query` モデルに `search_by_title` スコープを追加（`app/models/query.rb`）— `scope :search_by_title, ->(q) { q.present? ? where("title LIKE ?", "%#{sanitize_sql_like(q)}%") : all }`
  - 受け入れ条件: `Query.search_by_title("foo")` が SQLインジェクション文字列（`%`, `_`）をエスケープして安全に動作する（RSpec モデルスペックで確認）

### Dashboard 一覧・検索

- [ ] `DashboardsController#index` で `updated_at DESC` 順取得・タイトル部分一致検索を実装（`app/controllers/dashboards_controller.rb`）— `Query` と同様に `Dashboard.search_by_title(params[:q]).order(updated_at: :desc)`
  - 受け入れ条件: `GET /dashboards?q=foo` でタイトルに "foo" を含むダッシュボードのみが返る（RSpec リクエストスペックで確認）
- [ ] `Dashboard` モデルに `search_by_title` スコープを追加（`app/models/dashboard.rb`）— `Query` と同様の実装
  - 受け入れ条件: `Dashboard.search_by_title("")` が全件を返す（RSpec モデルスペックで確認）
- [ ] ダッシュボード一覧ビューに検索フォームと更新日時カラムを追加（`app/views/dashboards/index.html.erb`）— [[12-dashboard]] のビューを修正
  - 受け入れ条件: 検索フォームに入力して送信すると絞り込まれた一覧が表示される（System Spec `rack_test` で確認）

### RSpec

- [ ] `Query.search_by_title` の RSpec モデルスペック追加（`spec/models/query_spec.rb`）— キーワードあり・なし・特殊文字（`%`, `_`）のケースをカバー
  - 受け入れ条件: `bundle exec rspec spec/models/query_spec.rb` が全グリーン
- [ ] `Dashboard.search_by_title` の RSpec モデルスペック追加（`spec/models/dashboard_spec.rb`）— 同上
  - 受け入れ条件: `bundle exec rspec spec/models/dashboard_spec.rb` が全グリーン
- [ ] 一覧・検索の RSpec リクエストスペック追加（`spec/requests/queries_spec.rb`, `spec/requests/dashboards_spec.rb`）— 全件表示・キーワード一致・キーワード不一致（0件）・更新日順の各ケースをカバー
  - 受け入れ条件: 各スペックが全グリーン

## 動作確認

- [ ] クエリを複数作成し、`/queries` が `updated_at DESC` 順で表示される
- [ ] 検索フォームにキーワードを入力すると部分一致するクエリのみ表示される
- [ ] キーワードをクリアして検索すると全件に戻る
- [ ] ダッシュボードでも同様の動作を確認する
- [ ] `bin/rubocop` がエラーなし
- [ ] `bundle exec rspec` がグリーン、SimpleCov 85% 以上

## 未決事項・質問

なし
