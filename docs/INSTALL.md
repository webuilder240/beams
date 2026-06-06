# Beams インストール・運用ガイド（ONCE 配布）

Beams は **買い切り・自社サーバー設置型**の BI ツールとして、単一 Docker コンテナで配布する（ONCE 形態）。本書はまっさらな Linux サーバーへの設置から、バックアップ・自動アップデート・ロールバックまでの運用手順をまとめる。TLS 終端は ONCE プラットフォーム側に委ねるため、本書では扱わない（トピック 26 で `basecamp/once` 採用に移行中）。

> **注（2026-06-06）**: 旧自前配布層（自前インストーラ・自前 systemd 自動アップデート層・自前 TLS 設定など）はトピック 26 で `basecamp/once` 採用により全撤去された。本書の旧インストール／自動アップデート手順は同トピック・グループ F で ONCE プラットフォーム手順へ全面刷新する。

---

## 1. 前提

- **OS**: Linux（systemd を利用する場合は systemd ベースのディストリビューション）
- **Docker**: インストール済みであること（[Install Docker Engine](https://docs.docker.com/engine/install/)）。未導入の場合 `install.sh` は明示エラーで停止する。
- **権限**: root もしくは `sudo`（コンテナ起動・`/etc/beams/` 書き込み・systemd 設置のため）

---

## 2. インストール手順

> **手順は刷新中**: 旧 `install.sh` ベースの手順は撤去済み。ONCE プラットフォーム（`basecamp/once`）経由のインストール手順はトピック 26 グループ F で本節を全面刷新する予定。当面の暫定手順は本書下部「ONCE 環境変数」節を参照。

> **公式配布イメージ**: `ghcr.io/webuilder240/beams:latest`（`main` への push ごとに multi-arch でビルド・公開）。`:<git-sha>` タグでバージョン固定も可能。

---

## 3. 環境変数

| 変数 | 必須/任意 | 説明 |
|------|:---:|------|
| `RAILS_MASTER_KEY` | **必須** | `config/master.key` の値。Rails の暗号化資格情報（Active Record Encryption 等）の復号に使う。 |
| `IMAGE` | 任意 | 配布イメージ参照。既定 `ghcr.io/webuilder240/beams:latest`。バージョン固定したい場合は `ghcr.io/webuilder240/beams:<git-sha>` を指定する。 |

機密値（`RAILS_MASTER_KEY`）は `docker run -e` ではなく **ホスト env ファイル `/etc/beams/beams.env`（権限 600）経由（`docker run --env-file`）**で渡す。これにより鍵が `ps` などのプロセス一覧に現れず、コンテナ再生成後も同じ env ファイルを再利用できる。

---

## 4. ポート

Beams コンテナは **HTTP 80 のみ**を公開する（`-p 80:80`、Dockerfile も `EXPOSE 80`）。TLS 終端は ONCE プラットフォーム側で行うため、本コンテナ単体では HTTPS を扱わない。

### Thruster 関連 env と既定値

| env | 既定 | 説明 |
|-----|:---:|------|
| `HTTP_PORT` | `80` | Thruster の HTTP 待受ポート。 |
| `TARGET_PORT` | `3000` | Thruster が転送する先（Puma）のポート。 |

通常は既定のままでよい。コンテナの公開ポートは `-p 80:80` で固定する想定のため、`HTTP_PORT` を変更する場合は公開ポートも合わせて調整すること。

---

## 5. 永続データとバックアップ

- アプリの全永続データ（4 分割 SQLite DB・アップロード等）は named volume **`beams_storage`**（コンテナ内 `/rails/storage`）に保存される。コンテナを作り直してもデータは残る。
- SQLite の**自動バックアップ・復旧手順は [docs/RESTORE.md](RESTORE.md) を参照**（`rake beams:backup` / `rake beams:restore[generation]`）。バックアップ生成物も `/rails/storage` 配下（= `beams_storage`）に置かれる。

手動バックアップは稼働コンテナ内で実行する:

```bash
docker exec beams bundle exec rake beams:backup
```

---

## 6. ヘルスチェック

```bash
# HTTP
curl -fsS http://localhost/up
```

コンテナログは `docker logs -f beams` で確認できる。

---

## 7. 自動アップデート

> 旧自前 systemd 自動アップデート層は撤去済み（トピック 26）。自動アップデートは ONCE プラットフォーム側に一本化する。再生成時に `bin/boot` が 4 つの SQLite DB へ `db:prepare` を流すため、**マイグレーションは自動適用**される。具体的な ONCE 設定手順はトピック 26 グループ F で本節を全面刷新する。

---

## 8. 手動アップデート / ロールバック

> 旧 `install.sh` 経由の手動アップデート／ロールバック手順は撤去済み。ONCE プラットフォーム経由の手順はトピック 26 グループ F で本節を全面刷新する予定。永続データは named volume `beams_storage` に残るため、コンテナを差し替えてもデータは保持される。データ自体を以前の状態へ戻す必要がある場合は、バックアップ世代からの復旧（[docs/RESTORE.md](RESTORE.md) の `rake beams:restore[generation]`）を行う。

---

## ONCE 環境変数

> 本節は ONCE プラットフォーム（basecamp/once）採用への移行（トピック 26）に伴う暫定追記。INSTALL.md 全体は同トピック・グループ F で ONCE 手順へ全面刷新する。

### `RAILS_MASTER_KEY` の受け渡し

`RAILS_MASTER_KEY`（`config/master.key` の値）は ONCE の **custom env** として渡す。経路は次の 2 つ:

1. **CLI でインストール時に渡す**

   ```bash
   once install \
     --image ghcr.io/webuilder240/beams:latest \
     --env RAILS_MASTER_KEY=<config/master.key の値>
   ```

   `--env KEY=VALUE` は繰り返し指定できる。

2. **TUI で後から追加する**

   `once` を起動 → **Settings → Environment** フォームで `RAILS_MASTER_KEY` を行追加。保存後、ONCE が反映のためコンテナを再生成する。

`SECRET_KEY_BASE` は ONCE が初回インストール時に自動生成して以後保持するため、ユーザーが渡す必要はない（Rails 標準の env として自動的に拾われる）。`RAILS_MASTER_KEY` が未設定でも boot 自体は通るが、credentials（Active Record Encryption のキー 3 点を含む）を復号できないため、AR Encryption を使う機能は失敗する。

### Beams が使わない ONCE 経由 env

ONCE は他のアプリ向けに `VAPID_*` / `SMTP_*` / `NUM_CPUS` などの env を渡すことがある。**Beams はこれらを使っていない**（push 通知なし／メール送信は未実装／プロセス数は Puma の `WEB_CONCURRENCY` 等で制御）。**現状無視で問題ない**。将来これらを利用する機能を追加した時点で対応を検討する。

---

## バックアップ（ONCE 統合）

> 本節はトピック 26 グループ C で追記。INSTALL.md 全体はグループ F で ONCE 手順に全面刷新する。

自動バックアップは **ONCE プラットフォーム側に一本化**した。ONCE は設定されたスケジュール（保存先・頻度は TUI で設定）でバックアップを起動し、その直前に `/hooks/pre-backup` を呼び出す。Beams 側のフック実装（`bin/hooks/pre-backup` → `Beams::Once::PreBackup`）は、4 つの SQLite（`production` / `cache` / `queue` / `cable`）の整合性スナップショットを `/storage/backups/once-pending/` に書き出すだけで、世代管理・転送・暗号化は ONCE が担当する。

- **自動バックアップの設定**: ONCE TUI の Backups 画面（保存先・頻度・リテンション）
- **手動バックアップ（緊急時）**: 旧来の `rake beams:backup` / `bin/beams-backup` は**維持**する。`config/recurring.yml` での日次自動 enqueue は撤去済み（ONCE と二重に走らないため）。
- **復旧**: ONCE TUI からの復旧が標準。手動世代運用は [docs/RESTORE.md](RESTORE.md) を参照。

---

## 9. 関連ドキュメント

- バックアップ・復旧の詳細: [docs/RESTORE.md](RESTORE.md)
- 製品方針・配布形態: [docs/PRODUCT_PLAN.md](PRODUCT_PLAN.md)（§2 配布形態）
- 実装トピック: [docs/tasks/18-once-distribution.md](tasks/18-once-distribution.md)
