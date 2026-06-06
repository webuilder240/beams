# Beams 実装 — 作業進捗ログ（索引）

> 司令塔（マネージャー）が管理する進捗の索引。**詳細な時系列ログはトピックごとに `docs/tasks/progress/` 配下に分割**している。

- **体制**: 司令塔（マネージャー）1 / Coder 1 / Tester 1
- **運用ルール**:
  1. Coder は TDD（Red→Green→Refactor）で実装し、タスク完了ごとに人間がわかる単位でコミット → Tester にチェック依頼 → コンテキストをクリアして次へ。
  2. **DB マイグレーションは必ず事前に「確認用ドキュメント」を作成し、人間（ボス）の承認を得てから実行する。**
  3. Tester はコード品質ではなく「実装要件を満たしているか（QA）」を検証する。
  4. 司令塔は不明点を逐次人間に確認し、本ログから作業報告できるようにする。
- **進捗ログの分割**: トピックごとに `docs/tasks/progress/NN-<topic>.md` に時系列ログを記録する。

---

## トピック進捗サマリ

| # | トピック | ステータス | 担当 | 進捗ログ |
|---|----------|:---:|---|---|
| 01 | 基盤・Beamsリネーム | ✅完了 | - | （既存コミットで完了済み） |
| 02 | ONCE配布・プロセス管理 | ✅完了 | - | （既存コミットで完了済み） |
| 03 | 認証・ユーザー | ✅完了 | Coder/Tester | [progress/03-auth-users.md](progress/03-auth-users.md) |
| 04 | BigQuery接続 | ✅完了 | Coder/Tester | [progress/04-bigquery-connection.md](progress/04-bigquery-connection.md) |
| 05 | 初回セットアップウィザード | ✅完了 | Coder/Tester | [progress/05-setup-wizard.md](progress/05-setup-wizard.md) |
| 06 | スキーマブラウザ | ✅完了 | Coder/Tester | [progress/06-schema-browser.md](progress/06-schema-browser.md)（SolidCache方式・[ADR 0001](../adr/0001-bigquery-schema-cache.md)）|
| 07 | クエリエディタ | ✅完了 | Coder/Tester | [progress/07-query-editor.md](progress/07-query-editor.md) |
| 08 | コスト保護★ | ✅完了 | Coder/Tester | [progress/08-cost-protection.md](progress/08-cost-protection.md) |
| 09 | パラメータ化クエリ | ✅完了 | Coder/Tester | [progress/09-parameterized-query.md](progress/09-parameterized-query.md) |
| 10 | 非同期実行・結果保存 | ✅完了 | Coder/Tester | [progress/10-query-execution.md](progress/10-query-execution.md) |
| 11 | 可視化 | ✅完了 | Coder/Tester | [progress/11-visualization.md](progress/11-visualization.md) |
| 12 | ダッシュボード | ✅完了 | Coder/Tester | [progress/12-dashboard.md](progress/12-dashboard.md) |
| 13 | 共有・権限（組織フルオープン） | ✅完了 | Coder/Tester | [progress/13-sharing-permissions.md](progress/13-sharing-permissions.md) |
| 14 | 探しやすさ・一覧改善 | ✅完了 | Coder/Tester | [progress/14-search-listing.md](progress/14-search-listing.md) |
| 15 | SQLite自動バックアップ・復旧 | ✅完了 | Coder/Tester | [progress/15-backup-restore.md](progress/15-backup-restore.md) |
| 16 | フォームUIのTailwindスタイル統一 | ✅完了 | Coder/Tester | [progress/16-form-styling-consistency.md](progress/16-form-styling-consistency.md) |
| 17 | クエリ実行結果のレンダリング修正・実行履歴表示 | ✅完了 | Coder/Tester | [progress/17-query-result-history.md](progress/17-query-result-history.md) |
| 18 | KamalからONCE配信への移行 | ✅完了 | Coder/Tester | [manager/18-once-distribution.md](manager/18-once-distribution.md) |
| 19 | ダッシュボードD&D並び替え（Hotwire/SortableJS） | ✅完了 | Coder/Tester/Reviewer | [manager/19-dashboard-drag-drop.md](manager/19-dashboard-drag-drop.md) |
| 20 | SSO（Google OAuth ログイン） | ✅完了 | Coder/Tester/Reviewer | [manager/20-sso.md](manager/20-sso.md) |
| 21 | クエリ本文の SQL 検索（LIKE） | ✅完了 | Coder/Tester+Reviewer | [manager/21-sql-search.md](manager/21-sql-search.md) |
| 22 | Redash クエリ取り込み（API版） | ✅完了 | Coder/Tester/Reviewer | [manager/22-redash-import.md](manager/22-redash-import.md) |
| 23 | Bugsnag による例外通知 | ✅完了 | Coder | [progress/23-bugsnag-error-tracking.md](progress/23-bugsnag-error-tracking.md) |

> **20–22 は 2026-06-05 にユーザー指示で次フェーズとして分解、2026-06-06 に全決定事項確定。優先順は 20 → 21 → 22。**
> **23 は 2026-06-06 に運用品質向上トピックとして分解（B1-B4 確定済み・`/agent-team` 着手可）。**

---

## マイグレーション承認履歴

| トピック | マイグレーション | 確認ドキュメント | 承認 |
|---|---|---|:---:|
| 03 | `20260531000928_create_users` | [migrations/03-users-migration.md](migrations/03-users-migration.md) | ✅承認・実行済み |
| 04 | `20260531092141_create_bigquery_connections` | [migrations/04-bigquery-connections-migration.md](migrations/04-bigquery-connections-migration.md) | ✅承認・実行許可 |
| 07 | `20260531100000_create_queries` | [migrations/07-queries-migration.md](migrations/07-queries-migration.md) | ✅承認・実行済み |
| 08 | `20260531110000_create_application_settings` | [migrations/08-application-settings-migration.md](migrations/08-application-settings-migration.md) | ✅承認・実行済み |
| 09 | `20260531120000_create_query_parameters` | [migrations/09-query-parameters-migration.md](migrations/09-query-parameters-migration.md) | ✅承認・実行済み |
| 10 | `20260531130000_create_query_executions` | [migrations/10-query-executions-migration.md](migrations/10-query-executions-migration.md) | ✅承認・実行済み |
| 11 | `20260531140000_create_visualizations`（counter対応で修正後に再承認） | [migrations/11-visualizations-migration.md](migrations/11-visualizations-migration.md) | ✅承認・実行済み |
| 12 | `20260531150000_create_dashboards` / `20260531150001_create_widgets` | [migrations/12-dashboards-widgets-migration.md](migrations/12-dashboards-widgets-migration.md) | ✅承認・実行済み |
| 20 | `20260606000001_create_password_credentials_and_migrate` / `20260606000002_create_oauth_identities` / `20260606000003_add_allowed_email_domain_to_application_settings` | [migrations/20-users-oauth-migration.md](migrations/20-users-oauth-migration.md) | ✅承認・実行済み（破壊的：password_digest を別テーブルへ移行・カラム削除） |
| 22 | `20260606103507_create_redash_sources` | [migrations/22-redash-sources-migration.md](migrations/22-redash-sources-migration.md) | ✅承認・実行済み |

> ※ 05（セットアップウィザード）・06（スキーマブラウザ）は新規マイグレーション無し（06 は SolidCache 方式採用のため当初案のテーブルを廃止、[ADR 0001](../adr/0001-bigquery-schema-cache.md) 参照）。
> ※ 13（共有・権限）・14（探しやすさ）・15（バックアップ）はいずれも**新規マイグレーション無し**（13/14 は既存 `user_id`・`title` カラムを使用、15 はスキーマ変更なしの運用スクリプト）。承認ゲート対象外。
> ※ 21（SQL検索）は新規マイグレーション無し（既存 `queries.sql_body` を使う）。承認ゲート対象外。
> ※ 22（Redash取込）は **2026-06-06 にAPI版へ仕様変更**、`redash_sources` テーブル新規追加のためマイグレーション承認が必要。
