# 作業進捗ログ — トピック05: 初回セットアップウィザード

> タスク `docs/tasks/05-setup-wizard.md` の作業ログ（時系列）。司令塔・Coder・Tester のアクションを記録。

- **ステータス**: 🔄進行中
- **担当**: Coder

## 司令塔メモ（着手時の判断）

- **新規マイグレーション不要**（既存 `User` / `Bigquery::Connection` を使用）→ マイグレーション承認ゲートなし。
- **命名読み替え**: タスク doc の `Connection` / `Connection#test_connection` は確定仕様の **`Bigquery::Connection` / `Bigquery::Connection#test_connection`** に読み替える。
- **未決事項の方針（実装者判断、司令塔承認）**:
  - step3: `datasets.list` 権限があれば、データセット0件でも「成功」扱い。
  - 不足権限の抽出: BigQuery の API エラー（`Google::Cloud::PermissionDeniedError` 等）の message/reason から抽出。実装時にエラー形を確認。
  - 進行状況インジケータ: 共通パーシャルに切り出してよい（過剰設計しない）。
  - step4 のコスト上限: バイト整数をそのまま保存する最小実装。
  - ウィザード完了後のリダイレクト先: クエリ一覧は未実装のため当面 `root_path`（dashboard）へ。

## 時系列ログ

### 2026-05-31

- **司令塔**: トピック04完了を受け、依存（03・04）充足済みのトピック05に着手。新規 Coder をアサイン。マイグレーション不要のため承認ゲートなし。
</content>
