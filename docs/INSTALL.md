# Beams インストール・運用ガイド（ONCE プラットフォーム）

Beams は **買い切り・自社サーバー設置型**の BI ツールとして、単一 Docker コンテナで配布する。設置・自動アップデート・バックアップ・TLS 終端は [basecamp/once](https://github.com/basecamp/once)（37signals 製の ONCE プラットフォーム）に統合している。本書はまっさらな Linux サーバーへの設置から、バックアップ・アップデート・ロールバックまでの運用手順をまとめる。

> **公式配布イメージ**: `ghcr.io/webuilder240/beams:latest`（`main` への push ごとに multi-arch（`linux/amd64` / `linux/arm64`）でビルド・公開）。バージョン固定には `ghcr.io/webuilder240/beams:<git-sha>` タグを使う。

---

## 1. 前提

- **OS**: Linux（ONCE がサポートする Docker 動作環境）
- **Docker**: インストール済みであること（[Install Docker Engine](https://docs.docker.com/engine/install/)）
- **権限**: root もしくは `sudo`（ONCE CLI / TUI がコンテナ起動・ホストファイル書き込みを行うため）
- **DNS**: 公開ホスト名（例: `beams.example.com`）の **A レコード**を当該サーバーの公開 IP に向けておく。ONCE が Let's Encrypt で TLS 証明書を自動取得する際に必要

---

## 2. インストール

### 2.1 ONCE CLI / TUI を導入する

```bash
curl https://get.once.com | sh
```

### 2.2 Beams を設置する

2 経路ある。どちらでも結果は同じ。

#### 経路 A: TUI（対話型）

```bash
once
```

TUI で次のように進める:

1. "Enter a Docker image path" に `ghcr.io/webuilder240/beams:latest` を入力
2. hostname（例: `beams.example.com`）を入力
3. インストールを開始 → ONCE がイメージを pull し、コンテナを起動する

#### 経路 B: CLI 一発

```bash
once install --image ghcr.io/webuilder240/beams:latest
```

設置が完了すると Beams は HTTP 80 で待受を開始し、ONCE が TLS（HTTPS 443）を自動終端する。ブラウザで `https://<hostname>/` を開くと初回セットアップウィザード（admin 作成 → BigQuery 接続登録 → 接続テスト）に到達する。

`SECRET_KEY_BASE` は ONCE が初回インストール時に自動生成・永続化するため、ユーザーが渡す・管理する必要はない（Rails 標準の env として自動的に拾われる）。Beams は `config/credentials.yml.enc` を**持たない**ため、`RAILS_MASTER_KEY` / `config/master.key` も**不要**である（トピック27 で Active Record Encryption を撤廃済み。詳細は §3）。

---

## 3. セキュリティ上の注意

Beams は機微情報の暗号化を**アプリ層では行わない**。具体的には:

- **BigQuery サービスアカウント JSON 鍵**は `/storage/production.sqlite3` に**平文**で保存される（`bigquery_connections.service_account_json` text カラム）。
- **バックアップファイル**（`/storage/backups/*.sqlite3.gz`）も SQLite ダンプを gzip 圧縮しただけで**平文**。ONCE 経由の自動バックアップ（`/hooks/pre-backup` 経由で `/storage/backups/once-pending/` に書き出すスナップショット）も同様。

したがって SA 鍵漏洩を防ぐには以下のホスト側保護を運用者が用意すること:

1. **ホストディスクの暗号化**（LUKS など）— ストレージ媒体盗難対策。
2. **ファイルシステムパーミッション**— `/var/lib/docker/volumes/...`（ONCE が管理する `/storage` ボリュームのホスト実体）への root 以外のアクセスを禁止する。Beams コンテナは非 root（`uid 1000` rails ユーザー）で動作する。
3. **バックアップ転送経路の暗号化**— S3 等のリモート転送は ONCE 側で TLS / SSE を必ず有効化する。手動 `rake beams:backup` で生成した `*.sqlite3.gz` を外部に転送する場合も同様。
4. **BigQuery 側の最小権限**— Beams に渡す SA は閲覧対象データセットのみへの権限に絞り、漏洩時の被害を限定する。Connection 単位の `maximum_bytes_billed` を併用して暴走クエリの課金被害も抑制する（§4.4 計画書）。

なお、運用中の Beams インスタンスで `bin/rails credentials:edit` 等を実行して新たに `config/credentials.yml.enc` を生成する運用は**行わない**（生成しても Beams 本体は credentials を参照しない）。

---

## 4. バックアップ

### 4.1 自動バックアップ（ONCE 統合 / 推奨）

ONCE が定期バックアップを担う。ONCE TUI の **Backups 画面**で次を設定する:

- **保存先**: ローカルディスク / S3 / その他 ONCE がサポートするバックアップ先
- **頻度**: daily / weekly など
- **リテンション**: 保持世代数

バックアップ実行時、ONCE は Beams コンテナ内の `/hooks/pre-backup`（`bin/hooks/pre-backup` → `Beams::Once::PreBackup`）を呼び出す。Beams 側のフックは 4 つの SQLite DB（`production` / `cache` / `queue` / `cable`）の整合性スナップショットを `/storage/backups/once-pending/` に書き出すだけで、世代管理・転送・暗号化は ONCE が担当する。

### 4.2 手動バックアップ（緊急時用）

旧来の `rake beams:backup` / `bin/beams-backup` は **維持**している（緊急時の世代管理用）。`config/recurring.yml` での日次自動 enqueue は撤去済みのため、ONCE と二重に走ることはない。詳細は [docs/RESTORE.md](RESTORE.md) を参照。

```bash
# 稼働コンテナ内で実行
docker exec <container> bundle exec rake beams:backup
```

---

## 5. アップデート

ONCE 内蔵の **自動アップデート**に任せる。ONCE は定期的に `:latest` を pull し、新しいダイジェストがあればコンテナを再生成する。再生成時に Beams の `bin/boot` が 4 つの SQLite DB へ `db:prepare` を流すため、マイグレーションは自動適用される。

手動でアップデートしたい場合は次のいずれか:

- ONCE TUI の **action menu** から「Update」を選ぶ
- CLI: `once` の更新コマンドを叩く

---

## 6. ロールバック

不具合時は次のいずれかで戻す:

- **イメージタグ固定**: ONCE TUI でイメージパスを `ghcr.io/webuilder240/beams:<旧 git-sha>` に変更すると、ONCE がコンテナを再生成して当該イメージで起動する。`:latest` 追従に戻すには再度 `ghcr.io/webuilder240/beams:latest` を指定する
- **データ復旧**: アプリデータ自体を以前の状態へ戻す必要がある場合は、ONCE TUI の Backups 画面から世代復旧を行う。手動世代運用は [docs/RESTORE.md](RESTORE.md) の `rake beams:restore[generation]` を参照

---

## 7. ポート

Beams コンテナは **HTTP 80 のみ**を公開する（`Dockerfile` も `EXPOSE 80`）。TLS（HTTPS 443）終端は ONCE プラットフォーム側で自動的に行う（Let's Encrypt による証明書取得・更新も ONCE が担当）。

| env | 既定 | 説明 |
|-----|:---:|------|
| `HTTP_PORT` | `80` | Thruster の HTTP 待受ポート |
| `TARGET_PORT` | `3000` | Thruster が転送する先（Puma）のポート |

通常は既定のままでよい。

---

## 8. 環境変数

### 8.1 Beams が利用する env

| 変数 | 必須/任意 | 説明 |
|------|:---:|------|
| `DISABLE_SSL` | 任意 | ONCE が SSL 無効時に `true` を渡す。Beams は `DISABLE_SSL=true` 以外のときに `assume_ssl` / `force_ssl` を有効化し、`/up` を https リダイレクト対象から除外する（`Beams::Once::SslMode`） |
| `SECRET_KEY_BASE` | 自動 | ONCE が初回インストール時に自動生成・永続化する（運用者の操作は不要）。Rails 標準の env として `Rails.application.secret_key_base` が自動的に拾う |
| `BUGSNAG_API_KEY` | production のみ | Bugsnag への例外通知 API キー。ONCE custom env で渡す。development / test では未設定で問題ない |
| `APP_VERSION` | 任意 | Bugsnag イベントに付与するアプリバージョン。未設定でも動作に影響なし |
| `ONCE_PRE_BACKUP_DIR` | 任意 | `/hooks/pre-backup` の出力先（既定 `/storage/backups/once-pending`）。通常は変更不要 |

`RAILS_MASTER_KEY` は **不要**（トピック27 で Active Record Encryption を撤廃し `config/credentials.yml.enc` を同時に廃止したため）。ONCE TUI / CLI で渡す必要はない。

### 8.2 ONCE が渡しうるが Beams が使わない env

ONCE は他のアプリ向けに `VAPID_*` / `SMTP_*` / `NUM_CPUS` などの env を渡すことがある。**Beams はこれらを使っていない**（push 通知なし／メール送信は未実装／プロセス数は Puma の `WEB_CONCURRENCY` 等で制御）。**現状無視で問題ない**。将来これらを利用する機能を追加した時点で対応を検討する。

---

## 9. ヘルスチェック

```bash
# コンテナ内 / ローカル
curl -fsS http://localhost/up

# 公開 URL（ONCE が TLS 終端した状態）
curl -fsS https://<hostname>/up
```

コンテナログは ONCE TUI の Logs 画面、または `docker logs -f <container>` で確認できる。

---

## 10. 関連ドキュメント

- バックアップ・復旧の詳細: [docs/RESTORE.md](RESTORE.md)
- 製品方針・配布形態: [docs/PRODUCT_PLAN.md](PRODUCT_PLAN.md)（§2 配布形態）
- 実装トピック: [docs/tasks/26-once-platform.md](tasks/26-once-platform.md)（basecamp/once 採用への移行）／[docs/tasks/18-once-distribution.md](tasks/18-once-distribution.md)（旧自前配布層・履歴）
