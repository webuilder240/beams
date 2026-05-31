# トピック14: 探しやすさ・一覧改善 進捗（時系列）

## 2026-05-31 着手〜完了

- 事前調査: 既存カラムのみで実装可能、**マイグレーション不要**と判定（承認ゲート対象外）。
- Coder14 が TDD で実装:
  - `Query`: scope `search`（name + sql_text 部分一致）・`filter_by_creator`・`sorted_by`（`SORTABLE_COLUMNS = created_at/updated_at/name` のホワイトリスト経由で order 構築、不正値は既定にフォールバック）。
  - `Dashboard`: scope `search`（name + description）・`sorted_by`（同方式）。
  - `QueriesController#index` / `DashboardsController#index` で検索・絞り込み・並び替えを適用。
  - `SearchesController#index`（新規）＋ route `get "search", to: "searches#index"` で横断検索。
  - ビュー: queries/dashboards 一覧に検索/絞り込み/並び替え UI、searches/index に種別ごと件数表示・詳細リンク、layouts にヘッダー検索ボックス。
  - 追加 spec: model（scope・不正sort フォールバック）/ request（/search・sort・q・creator・未ログインリダイレクト）/ system（操作フロー・横断検索）。
- Tester14 が独立検証（コード確認・rspec再実行・runner検算で SQLインジェクション耐性確認・lint/security再実行）で **PASS**。

## 結果
- rspec: 489 examples / 0 failures、SimpleCov 98.61%（≥85%）
- rubocop: 0 offenses / brakeman: 0 warnings（SQL injection 警告なし）
- コミット: 7e3a210（scope + model spec）, 9c1b4d8（一覧 UI + request/system spec）, b5f80a2（横断検索 SearchesController + spec）

## 要件チェック
- 14.1 名前+SQL本文検索・並び替え・作成者絞り込み ✅
- 14.2 名前+説明検索・並び替え ✅
- 14.3 ヘッダー横断検索・種別ごと表示・件数表示 ✅
- 14.4 GET /search・詳細リンク ✅
