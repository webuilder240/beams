# トピック21: クエリ本文の SQL 検索（LIKE）

> 既存のタイトル部分一致検索（[[14-search-listing]] で実装済み）を拡張し、SQL 本文も LIKE で検索できるようにする。
> 計画書 §7「タグ / お気に入り / SQL全文検索」のうち、SQL検索のみを **FTS5 は使わず LIKE で実装**する（ユーザー判断: 2026-06-05）。

- **ステータス**: 未着手（**全決定事項B1-B3 確定済み 2026-06-06**・`/agent-team` 着手可）
- **依存**: [[14-search-listing]]（`Query.title_matching` スコープと検索フォームが完了済み）/ [[07-query-editor]]（`Query.sql_body` カラム）
- **関連計画書**: §7（将来項目を一部実装）

---

## ボス決定事項（**全項目確定 2026-06-06**）

| ID | 決定内容 |
|---|---|
| **B1** ✅ | **既存の単一入力欄を「タイトル＋SQL本文」のOR検索に変更**。placeholder を「タイトル/SQL本文で検索」に変更するだけ |
| **B2** ✅ | **`Query.title_matching` を `text_matching` にリネーム**。中身を `title OR sql_body` のOR検索に置換 |
| **B3** ✅ | **ダッシュボード一覧は従来通りタイトル検索のまま**。SQL検索はクエリ一覧のみ |

---

## ゴール（完了の定義）

- `GET /queries?q=foo` がタイトル **または** SQL本文に "foo" を含むクエリにマッチする（OR検索）
- 既存のタイトル部分一致検索の挙動を壊さない（タイトルだけ一致するクエリも引き続きヒット）
- SQLインジェクション・LIKE特殊文字（`%`/`_`/`\`）は安全にエスケープされる（`sanitize_sql_like` + `ESCAPE '\'`）
- 検索キーワード未指定（空文字・nil）は全件を返す
- マッチ件数や行ハイライトは表示しない（最小実装）
- FTS5・全文検索インデックスは導入しない
- ダッシュボード一覧は従来通り（B3-A）
- RSpec が通り、SimpleCov 85% 以上を維持

---

## 前提・参照（実読済み）

- `app/models/query.rb` の `title_matching` スコープ:
  ```ruby
  scope :title_matching, ->(term) {
    next all if term.blank?
    where("title LIKE ? ESCAPE '\\'", "%#{sanitize_sql_like(term)}%")
  }
  ```
  → これを拡張する。
- `app/controllers/queries_controller.rb#index`:
  ```ruby
  @queries = Query.title_matching(params[:q]).order(updated_at: :desc)
  ```
  → スコープ名を差し替えるだけで動く。
- `app/views/queries/index.html.erb` の検索フォーム — `placeholder: "タイトルで検索"` だけ更新する。
- DB変更は**不要**（`queries.title` `string`・`queries.sql_body` `text` が既に存在）。
- SQLite の LIKE は ASCII 大文字小文字非依存（マルチバイトはバイナリ比較になるが、SQL文中の英数字検索は実用上問題なし）。

---

## タスク

### モデル

- [ ] `Query.title_matching` を `Query.text_matching` にリネームし、`title OR sql_body` のOR検索にする（`app/models/query.rb`）
  ```ruby
  scope :text_matching, ->(term) {
    next all if term.blank?

    pattern = "%#{sanitize_sql_like(term)}%"
    where("title LIKE :p ESCAPE '\\' OR sql_body LIKE :p ESCAPE '\\'", p: pattern)
  }
  ```
  - 受け入れ条件:
    - `Query.text_matching("foo")` が title または sql_body に "foo" を含むレコードを返す
    - 空文字・nil は `all` を返す
    - `%` `_` `\` を含む検索語はリテラル一致する（モデルスペック）

### コントローラ

- [ ] `QueriesController#index` のスコープ呼び出しを `text_matching` に変更（`app/controllers/queries_controller.rb`）
  - 受け入れ条件: `GET /queries?q=foo` が新スコープで動作する（リクエストスペック）。

### ビュー

- [ ] `app/views/queries/index.html.erb` の `search_field :q` の `placeholder` を「タイトル/SQL本文で検索」に変更
  - 受け入れ条件: 画面に新しい placeholder が表示される（System Spec `rack_test`）。

### テスト

- [ ] `spec/models/query_spec.rb` に `text_matching` のスペックを追加（既存の `title_matching` テストは置換）
  - ケース:
    - title のみマッチ
    - sql_body のみマッチ
    - 両方マッチ（重複しない）
    - どちらにもマッチしない（空配列）
    - 空文字・nil（全件返却）
    - LIKE 特殊文字 `%`/`_`/`\` のエスケープ
  - 受け入れ条件: 全 green。
- [ ] `spec/requests/queries_spec.rb` の検索テストに「SQL本文のみマッチするクエリ」が抽出されるケースを追加
  - 受け入れ条件: green。
- [ ] `spec/system/queries_spec.rb`（`rack_test`）に SQL本文検索の E2E ケースを追加
  - タイトル "Untitled"、SQL本文 "SELECT user_id FROM events" のクエリを作り、`q=user_id` で検索 → ヒット
  - 受け入れ条件: green。

### 既存テストの修正

- [ ] `title_matching` を参照している既存スペック・ヘルパーがあれば `text_matching` に置換（grep 確認）
  - 受け入れ条件: `grep -rn "title_matching" app/ spec/` が0件。

---

## 動作確認

- [ ] クエリAをタイトル "売上集計"、SQL本文 `SELECT SUM(amount) FROM orders` で作成
- [ ] クエリBをタイトル "ユーザー数"、SQL本文 `SELECT COUNT(*) FROM users` で作成
- [ ] `/queries?q=売上` → クエリAのみヒット（タイトル一致）
- [ ] `/queries?q=orders` → クエリAのみヒット（SQL本文一致）
- [ ] `/queries?q=users` → クエリBのみヒット（SQL本文一致）
- [ ] `/queries?q=` → 全件（並びは `updated_at DESC`）
- [ ] `/queries?q=%` → 0件（特殊文字がリテラル扱いされること）
- [ ] `bundle exec rspec` 全 green、SimpleCov 85% 以上
- [ ] `bin/rubocop` クリーン

---

## 未決事項・質問

なし（B1〜B3 はすべて確定済み 2026-06-06）。`/agent-team` 着手可。
