# 作業進捗ログ — トピック08: コスト保護（dry-run・上限ガード）★

> タスク `docs/tasks/08-cost-protection.md` の作業ログ（時系列）。司令塔・Coder・Tester のアクションを記録。

- **ステータス**: 🔄進行中
- **担当**: Coder

## 司令塔メモ（着手時の判断・未決事項の決定）

- **新規マイグレーション必要**: `application_settings` テーブル（コスト単価のシングルトン設定）→ マイグレーション承認ゲート。
- **未決事項Dの決定**: 換算レートは **グローバル1設定**（`ApplicationSetting` シングルトン、`bigquery_yen_per_tb` decimal、デフォルト950.0）。Connection 単位ではない。タスク doc グループ2 も ApplicationSetting 前提で整合。
- **dry-run のSQL取得元**: ルートは `POST /queries/:query_id/dry_run`（接続コンテキスト取得用）。ただし **SQL本文はリクエストボディの現在のエディタ内容を使用**（ライブ編集中のコスト確認を成立させる。未保存の新規クエリは保存後に確認）。BigQuery 側 dry-run なので SQL を body で受けてもセキュリティ上問題なし。
- **命名**: `ApplicationSetting` はフラットなトップレベル（汎用シングルトン設定。将来他設定も保持し得る）。dry-run/コスト換算ロジックは PORO（`app/models/dry_run.rb` / `app/models/cost_estimate.rb`）と `Bigquery::Connection#over_limit?` に置く（`*Service` 禁止）。
- **命名読み替え**: タスク doc の `Connection#over_limit?` / `Connection#maximum_bytes_billed` は `Bigquery::Connection` に読み替え。`DryRun.new(connection, sql)` の connection は `Bigquery::Connection`。

## 時系列ログ

### 2026-05-31

- **司令塔**: トピック07完了を受け、依存（04・07）充足済みのトピック08（コスト保護★）に着手。新規 Coder をアサイン。`application_settings` テーブルのマイグレーションが必要 → 承認ゲート。確認用ドキュメント作成を指示。
- **Coder→司令塔**: `application_settings` マイグレーション＋確認ドキュメント作成。論点3点（precision(10,2) / デフォルト950.0 / シングルトンはアプリ層担保）を提起。司令塔: いずれも妥当と承認。
- **司令塔→人間**: `application_settings` マイグレーション承認を依頼。
- **人間→司令塔**: ✅承認。`db:migrate` 実行を許可。
- **司令塔→Coder**: マイグレーション実行＋トピック08 本実装（TDD）を指示。
