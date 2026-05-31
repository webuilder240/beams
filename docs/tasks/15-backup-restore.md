# トピック15: SQLite 自動バックアップ・復旧

> 4つのSQLite DB（primary/cache/queue/cable）を稼働中でも安全にバックアップし、バックアップから復旧できるスクリプトと自動実行を整備する。計画書 §2.1（永続データは `/storage` 配下）/ §6.3（SQLite肥大化抑制）に関連。

- **ステータス**: ✅完了
- **依存**: [[01-foundation-rename]]（4分割DB・モジュール名確定）、[[02-once-deployment]]（`/storage` 永続化・worker プロセス・`bin/boot`）
- **関連計画書**: §2.1, §2.2, §3.1, §6.3, §6.5

## ゴール（完了の定義）

- `bin/backup` 一発で、稼働中（WALモード書き込み中）でも **整合性のとれた** 4DBのバックアップが `/storage/backups/` 配下に作成される
- バックアップは gzip 圧縮され、世代管理（保持件数を超えた古い世代は自動削除）される
- 各バックアップ取得後に `PRAGMA integrity_check` で健全性が検証される
- `bin/restore <backup_dir_or_timestamp>` で、指定世代のバックアップから4DBを復旧できる（手順含めてスクリプト化）
- バックアップが **SolidQueue の定期実行（`config/recurring.yml`）** で自動的に走る（外部 cron 依存なし＝ONCE思想）
- バックアップ・復旧の振る舞いが RSpec で検証されている

## 前提・参照

- `config/database.yml` — production の4分割（`storage/production.sqlite3` / `_cache` / `_queue` / `_cable`）。Rails 8 の SQLite はデフォルト **WALモード**
- **WALモードの注意**: `.sqlite3` 本体ファイルを単純 `cp` すると、未チェックポイントの `-wal` / `-shm` の内容が反映されず壊れた/古いバックアップになり得る。**オンラインバックアップAPI（`sqlite3 ... ".backup"` または `VACUUM INTO`）を使い、単一ファイルの一貫スナップショットを取る**こと
- `/storage` は [[02-once-deployment]] によりONCEがファイル単位で自動バックアップする領域。本トピックはその上で **アプリ管理の世代バックアップ** を追加で持つ（ポイントインタイム復旧・誤操作復旧のため）
- 復旧の対象は基本 `production.sqlite3`（メインデータ）。`_cache` / `_cable` は再生成可能、`_queue` は未処理ジョブを含むため任意で対象化（→ 未決事項）
- `config/recurring.yml` — SolidQueue の定期実行定義ファイル（既存）

## タスク

### バックアップスクリプト

- [ ] バックアップ対象DBの一覧と出力先 `/storage/backups/<timestamp>/` を決めるロジックを実装する（`bin/backup` から呼ぶ Ruby スクリプト or rake タスク） (`bin/backup`, `lib/tasks/backup.rake`, `lib/beams/backup.rb`)
  - 受け入れ条件: `database.yml` の production 4DBのパスを動的に取得し、存在するDBのみ対象にする
- [ ] 各DBを **オンラインバックアップ**（`VACUUM INTO '/storage/backups/<timestamp>/<name>.sqlite3'` もしくは `sqlite3 src ".backup 'dst'"`、または sqlite3 gem の `SQLite3::Database#backup`）で一貫スナップショット取得する (`lib/beams/backup.rb` の `Beams::Backup`)
  - 受け入れ条件: DBへ書き込みが走っている最中でも、取得したバックアップが破損せず開ける（WAL未チェックポイント分も含まれる）
- [ ] 取得したスナップショットを gzip 圧縮する（`<name>.sqlite3.gz`） (`lib/beams/backup.rb` の `Beams::Backup`)
  - 受け入れ条件: `/storage/backups/<timestamp>/production.sqlite3.gz` 等が生成される
- [ ] 各バックアップに対し `PRAGMA integrity_check` を実行し、`ok` 以外なら失敗として記録・通知する (`lib/beams/backup.rb` の `Beams::Backup`)
  - 受け入れ条件: 健全なら成功ログ、破損を検知したらそのバックアップを失敗扱いにしエラーを残す
- [ ] バックアップのメタ情報（取得時刻・対象DB・サイズ・integrity結果）を `manifest.json` として同ディレクトリに残す (`/storage/backups/<timestamp>/manifest.json`)
  - 受け入れ条件: 各世代に manifest が存在し、復旧スクリプトが世代を識別できる

### 世代管理（ローテーション）

- [ ] 保持世代数（例: 直近7世代）を設定で持ち、超過した古い世代ディレクトリを自動削除する (`Beams::Backup` 内の定数 or `config/beams.yml`)
  - 受け入れ条件: 保持数を超えると最古の世代が削除され、`/storage/backups/` が無制限に肥大化しない（=ONCEバックアップ肥大も抑制）
- [ ] 保持数・スケジュール等の設定値を1箇所に集約する（`config/beams.yml` 等、過剰設計しない） (`config/beams.yml` または既存設定モデル)
  - 受け入れ条件: 保持世代数とバックアップ間隔がコード散在せず1箇所で変更できる

### 自動実行（SolidQueue 定期実行）

- [ ] バックアップを実行する Job を作成する（`Beams::Backup` を呼ぶだけの薄いジョブ） (`app/jobs/backup_job.rb`)
  - 受け入れ条件: `BackupJob.perform_now` で1世代のバックアップが作成される
- [ ] `config/recurring.yml` に日次（または設定間隔）で `BackupJob` を登録する (`config/recurring.yml`)
  - 受け入れ条件: worker プロセス（[[02-once-deployment]] の `bin/jobs`）稼働時にスケジュール通り `BackupJob` がenqueueされる
- [ ] 手動実行用の `bin/backup` ラッパーを用意する（運用者がいつでも1世代取得できる） (`bin/backup`)
  - 受け入れ条件: `bin/backup` 実行で即座に1世代が作成され、終了コードで成否が分かる

### 復旧スクリプト

- [ ] 復旧対象世代を引数で受け取る `bin/restore` を作成する（タイムスタンプ or `latest`） (`bin/restore`, `lib/tasks/restore.rake`, `lib/beams/restore.rb` の `Beams::Restore`)
  - 受け入れ条件: `bin/restore latest` / `bin/restore <timestamp>` で対象世代を特定できる。引数なし時は利用可能な世代一覧を表示する
- [ ] 復旧前に現行DBを退避（`*.sqlite3.bak` 等にリネーム）し、gzip を解凍して所定パスへ展開する (`lib/beams/restore.rb` の `Beams::Restore`)
  - 受け入れ条件: 復旧失敗時に退避した現行DBへロールバックできる
- [ ] 復旧手順に「書き込み停止」を組み込む（ONCE単一コンテナ前提: 復旧は **コンテナ/プロセス停止中** に行う想定。`bin/restore` は web/worker 停止を前提とする旨をスクリプト冒頭で警告・確認する） (`bin/restore`)
  - 受け入れ条件: 稼働中DBへの上書きでファイル破損を起こさない手順になっている（停止確認 or `--force`）
- [ ] 復旧後に `db:migrate`（スキーマ差分吸収。ONCE自動アップデートで新スキーマの可能性があるため）と `PRAGMA integrity_check` を実行する (`bin/restore`)
  - 受け入れ条件: 復旧したDBが現行アプリのスキーマで起動でき、integrity が `ok`
- [ ] 復旧の手順書（前提・コマンド・ロールバック）を `docs/` に短くまとめる (`docs/RESTORE.md`)
  - 受け入れ条件: 運用者が手順書だけ見て復旧操作を完遂できる

### テスト（TDD: 先に失敗する RSpec を書いてから実装する。テスト green になるまでタスク完了にしない）

- [ ] `Beams::Backup` のスペック: 一時DBに書き込みつつバックアップを取り、復元したDBに同データが入っていることを検証する (`spec/lib/beams/backup_spec.rb`)
  - 受け入れ条件: バックアップ→解凍→オープン→件数一致、integrity ok を検証。カバレッジ85%以上
- [ ] `Beams::Restore` のスペック: バックアップから復旧し、現行DBが退避・置換されることを検証する (`spec/lib/beams/restore_spec.rb`)
  - 受け入れ条件: 復旧後にデータが一致し、失敗時ロールバックが効く。カバレッジ85%以上
- [ ] ローテーションのスペック: 保持数超過で最古世代が削除されることを検証する (`spec/lib/beams/backup_spec.rb`)
  - 受け入れ条件: 保持数=N のとき N+1 回取得すると最古が消える

## 動作確認

- [ ] `bin/backup` を実行 → `/storage/backups/<timestamp>/` に4DB（または対象DB）の `.sqlite3.gz` と `manifest.json` が生成される
- [ ] アプリへ書き込み（レコード作成）した直後に `bin/backup` → 復旧したバックアップにその書き込みが含まれる（WAL整合の確認）
- [ ] 保持世代数を超えるまで `bin/backup` を繰り返し、最古世代が自動削除される
- [ ] worker 稼働状態でスケジュール時刻に `BackupJob` が走る（`config/recurring.yml` 連携）
- [ ] `bin/restore latest` でDBが復旧し、`bin/rails s` が正常起動、`PRAGMA integrity_check` が `ok`

## 未決事項・質問

- バックアップ対象を **primary のみ** にするか、4DB全部にするか。`_cache`/`_cable` は再生成可能だが、`_queue` は未処理ジョブを含む。最小は primary のみ＋queue。要方針決定。
- バックアップ手法は `VACUUM INTO`（断片化解消も兼ねるが対象DBをロックする瞬間がある）と `.backup`/`SQLite3#backup`（ページ単位でロック影響が小さい）のどちらを採るか。稼働中の書き込み量で選択。
- バックアップの保存先を `/storage/backups/`（ONCEの自動バックアップ対象＝二重保全だが容量増）にするか、`/storage` 外（ONCE対象外だがコンテナ消失で失う）にするか。ONCE思想なら `/storage` 配下が自然。
- バックアップ間隔（日次/時次）と保持世代数のデフォルト値。`/storage` 容量と復旧粒度のトレードオフ。
- オフサイト（S3/GCS等の外部ストレージ）への退避は初期スコープか。計画書は「外部サービス依存なし」を掲げるため、初期はローカル `/storage` のみが整合的（→ 将来オプション）。
- 復旧時の「書き込み停止」をどう担保するか。ONCE単一コンテナではコンテナ停止が前提だが、稼働中復旧を許す場合はメンテナンスモードが要る。
