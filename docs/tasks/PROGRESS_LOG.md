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
| 05 | 初回セットアップウィザード | 🔄進行中 | Coder | [progress/05-setup-wizard.md](progress/05-setup-wizard.md) |
| 06 | スキーマブラウザ | ⏳未着手 | - | - |
| 07 | クエリエディタ | ⏳未着手 | - | - |
| 08 | コスト保護 | ⏳未着手 | - | - |
| 09 | パラメータ化クエリ | ⏳未着手 | - | - |
| 10 | 非同期実行・結果保存 | ⏳未着手 | - | - |
| 11 | 可視化 | ⏳未着手 | - | - |
| 12 | ダッシュボード | ⏳未着手 | - | - |
| 13 | 共有・権限 | ⏳未着手 | - | - |
| 14 | 探しやすさ・一覧検索 | ⏳未着手 | - | - |
| 15 | SQLite自動バックアップ | ⏳未着手 | - | - |

---

## マイグレーション承認履歴

| トピック | マイグレーション | 確認ドキュメント | 承認 |
|---|---|---|:---:|
| 03 | `20260531000928_create_users` | [migrations/03-users-migration.md](migrations/03-users-migration.md) | ✅承認・実行済み |
| 04 | `20260531092141_create_bigquery_connections` | [migrations/04-bigquery-connections-migration.md](migrations/04-bigquery-connections-migration.md) | ✅承認・実行許可 |
</content>
