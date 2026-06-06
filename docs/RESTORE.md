# SQLite バックアップ・復旧手順

Beams の SQLite データベース（`production` / `cache` / `queue` / `cable`）の
バックアップと復旧手順をまとめる。実装はトピック15。

> **トピック 26（ONCE プラットフォーム移行）以降の方針**: 自動バックアップは ONCE
> プラットフォーム（basecamp/once）TUI で設定する。ONCE はバックアップ前に
> `/hooks/pre-backup`（`bin/hooks/pre-backup` → `Beams::Once::PreBackup`）を呼び
> `/storage/backups/once-pending/` に整合性スナップショットを配置し、その後
> 世代管理・転送・暗号化を担当する。本書で扱う `rake beams:backup` /
> `rake beams:restore[generation]` は **手動緊急時の世代管理用**として維持する
> （`config/recurring.yml` での日次自動 enqueue は撤去済み）。

## 仕組み

- バックアップは SQLite のオンラインバックアップ（`VACUUM INTO`）で一貫スナップ
  ショットを取得する。WAL モードで書き込み中でも壊れたバックアップにならない。
- 1 回の実行で `<BEAMS_BACKUP_DIR>/<timestamp>/` ディレクトリを作り、各 DB を
  `*.sqlite3.gz`（gzip 圧縮）として保存し、`manifest.json`（取得時刻・対象 DB・
  サイズ・`PRAGMA integrity_check` 結果）を残す。
- 保持世代数を超えた古い世代ディレクトリは自動削除される（ローテーション）。
- 自動実行は SolidQueue の定期実行（`config/recurring.yml` の `daily_backup`）で
  行う。外部 cron 不要。worker プロセス稼働が前提。

## 設定（環境変数）

| 変数 | 既定値 | 説明 |
|------|--------|------|
| `BEAMS_BACKUP_DIR` | `storage/backups` | バックアップ保存先ルート |
| `BEAMS_BACKUP_GENERATIONS` | `7` | 保持する世代数 |

## バックアップ

```bash
bin/beams-backup            # 1 世代を即時取得（cron からも可）
bundle exec rake beams:backup
bundle exec rake beams:backup:list   # 利用可能な世代を新しい順に表示
```

成功すると `<BEAMS_BACKUP_DIR>/<timestamp>/production.sqlite3.gz` 等が生成される。

## 復旧

> WARNING: 復旧は DB ファイルを上書きする。**web / worker プロセスを停止**して
> から実行すること（単一コンテナ / ONCE 前提）。現行 DB は
> `<db>.<timestamp>.bak` として退避され、途中で失敗した場合は自動ロールバック
> される。

```bash
# 利用可能な世代を確認
bin/beams-restore
# 最新世代から復旧
bin/beams-restore latest
# タイムスタンプ指定で復旧
bin/beams-restore 20260531T090000Z

# rake 版
bundle exec rake 'beams:restore[latest]'
```

### 復旧後の手順

1. スキーマ差分を吸収する:
   ```bash
   bin/rails db:migrate
   ```
2. 健全性を確認する（各 DB が `ok` を返すこと）:
   ```bash
   sqlite3 storage/production.sqlite3 'PRAGMA integrity_check'
   ```
3. プロセスを再起動して `bin/rails s` 等が正常起動することを確認する。

### ロールバック（復旧をやり直す）

復旧で問題が起きた場合、退避された安全コピーから手動で戻せる。

```bash
mv storage/production.sqlite3 storage/production.sqlite3.failed
mv storage/production.sqlite3.<timestamp>.bak storage/production.sqlite3
```
