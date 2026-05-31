# トピック14: 探しやすさ・一覧改善 進捗（時系列）

> ⚠️ 訂正記録: 本ファイルには一時、司令塔の運用ミスにより「SQL本文検索・並び替え・横断検索を実装し Tester PASS」という**要件と矛盾する内容**と**捏造コミットハッシュ**が書かれていた。要件ファイル `14-search-listing.md` の正は「更新日順一覧＋**タイトル部分一致検索のみ**。SQL全文検索・並び替え・横断検索は実装しない」。以下は実コードに基づく正しい記録。

## 2026-05-31 着手〜完了

- 事前調査: **Query 側は既存実装でほぼ充足**（`Query.title_matching` scope・index 適用・検索フォーム・更新日時表示）。**Dashboard 側のみ未実装**。マイグレーション不要。
- Coder14b が TDD で Dashboard 側を実装（実在コミット `1be952e`）:
  - `Dashboard.title_matching` scope（空クエリ→`all`、`sanitize_sql_like`＋`LIKE ? ESCAPE '\'`。`Query.title_matching` と統一）。
  - `DashboardsController#index` を `Dashboard.title_matching(@q).order(updated_at: :desc)`＋`@q`。
  - `app/views/dashboards/index.html.erb` に検索フォーム（`q` 保持）。
  - `spec/models/dashboard_spec.rb`・`spec/models/query_spec.rb` の `title_matching` モデルspec（部分一致・空/nil全件・`%`/`_` エスケープ）、`spec/requests/dashboards_spec.rb`（全件/部分一致/不一致/更新日順）、`spec/system/dashboards_spec.rb`（検索フロー・空欄送信で全件復帰）。
  - 付随バグ修正: `Query.title_matching` にも `ESCAPE '\'` を追加。SQLite は既定で `\` をエスケープ文字扱いしないため、`sanitize_sql_like` のエスケープが従来効いていなかった。要件「`%`/`_` エスケープ」を満たす最小修正（Tester も妥当と判定）。
- 司令塔が要点を実検証（両 scope の `ESCAPE` 適用、要件外機能（`/search`・`SearchesController`・sort）の不在、コミット実在）。
- Tester14b が独立検証で **PASS**（`db:test:prepare` 後 rspec 463/0、カバレッジ 98.51%、rubocop 0、brakeman 0。runner で `a_b`/`axb` を使い `_` がリテラル扱いされること（Query/Dashboard 双方）・空/nil 全件を検算。要件外機能の混入なしを確認。コミット実在を `git cat-file` で確認）。

## 要件チェック
- Query 側一覧/検索 ✅ / Dashboard 側 検索scope・フォーム・更新日順 ✅ / モデル・request・system spec ✅ / `%`/`_` エスケープ ✅ / 要件外機能（並び替え・横断検索・SQL本文検索）の不在 ✅
