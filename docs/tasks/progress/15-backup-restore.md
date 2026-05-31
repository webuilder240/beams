# トピック15: SQLite自動バックアップ・復旧 進捗（時系列）

> ⚠️ 訂正記録: 本ファイルには一時、Coder/Tester を同時起動した運用ミスにより不正確な完了記録（捏造コミットハッシュ含む）が書かれ、さらに「自動実行(recurring.yml登録)」が未実装のまま完了扱いになっていた。以下は実コードに基づく正しい記録。

## 2026-05-31 着手〜完了

- 実装（`lib/` モジュール＋rake/bin ラッパー＋`spec/lib/`。`*Service` 不使用）:
  - `lib/beams/backup.rb`（`Beams::Backup`）: `VACUUM INTO`（バインド変数）でオンラインスナップショット → gzip 圧縮（`Zlib::GzipWriter`、`.sqlite3.gz`）→ `PRAGMA integrity_check` → `manifest.json` 記録 → 世代ローテーション（`rotate!`）。`BEAMS_BACKUP_DIR`（既定 storage/backups）・`BEAMS_BACKUP_GENERATIONS`（既定7）で設定。コミット `125b7c6`。
  - `lib/beams/restore.rb`（`Beams::Restore`）: `latest`/世代指定の解決、復元前に現DBを `.bak-<timestamp>` 退避、失敗時ロールバック、存在しない世代は `ArgumentError`。コミット `f5ecb54`。
  - `app/jobs/backup_job.rb`（`BackupJob`、`perform` で `Beams::Backup.new.run`）、`lib/tasks/beams.rake`（`beams:backup`／`beams:backup:list`／`beams:restore[generation]`）、`bin/beams-backup`／`bin/beams-restore`（実行権限 100755）、`docs/RESTORE.md`。コミット `4ccc26a`。`1ac1ad0`（VACUUM INTO 採用）、`f9d3f55`（restore ロールバック修正）。
  - **不足分の補完**: `config/recurring.yml` の `production:` に `daily_backup: { class: BackupJob, queue: default, schedule: every day at 3am }` を追加し、`spec/config/recurring_spec.rb` で登録（class: BackupJob・schedule: every day）を検証。コミット `2b6f5d5`。
- 司令塔が要点を実検証（recurring.yml の BackupJob 日次登録・spec 3例 green）。
- Tester15b が独立検証で **PASS**（`db:test:prepare` 後 rspec 447/0、カバレッジ 97.6%、rubocop 0、brakeman 0。一時ディレクトリ tmp/qa15 で rake backup／list／世代ローテーション（generations=2 で最古削除→2世代残存）／restore（元データ復元＋.bak退避）／存在しない世代で ArgumentError を実挙動検算。開発/test DB 不可侵。コミット `125b7c6`/`f5ecb54`/`4ccc26a`/`2b6f5d5` 実在を確認）。

## 要件チェック
- 15.1 オンラインバックアップ（VACUUM INTO）・gzip・integrity_check・manifest ✅
- 15.2 世代管理（保持N世代・超過削除）✅
- 15.3 自動実行（`config/recurring.yml` に日次 BackupJob 登録）✅
- 15.4 復旧（latest/指定世代・退避・ロールバック・例外）✅
- 15.5 rake（backup/list/restore）・bin ラッパー（実行権限100755）✅
- 15.6 設定（環境変数）・spec（lib/jobs/config）✅

## 申し送り
- 要件文言のパス例（`bin/backup`/`bin/restore`/`lib/tasks/backup.rake`）と実装（`bin/beams-backup`/`bin/beams-restore`/`lib/tasks/beams.rake`）に命名差があるが、機能は全充足のため許容（`beams-`/`beams:` はアプリ名前空間として妥当）。
- test DB に残留データがあると setup_wizard 系9件が誤って失敗する。検証前に必ず `bin/rails db:test:prepare`。
