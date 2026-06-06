# Beams インストール・運用ガイド（ONCE 配布）

Beams は **買い切り・自社サーバー設置型**の BI ツールとして、単一 Docker コンテナで配布する（ONCE 形態）。本書はまっさらな Linux サーバーへの設置から、バックアップ・自動アップデート・ロールバックまでの運用手順をまとめる。TLS 終端は ONCE プラットフォーム側に委ねるため、本書では扱わない（トピック 26 で `basecamp/once` 採用に移行中）。

> 配布物の実体は次の通り。本書のコマンド・パス・変数はこれらと一致している。
> - インストーラ: `deploy/once/install.sh`
> - 自動アップデート: `bin/once-update` / `deploy/once/once-update.service` / `deploy/once/once-update.timer`
> - アップデートロジック: `lib/beams/once/updater.rb`

---

## 1. 前提

- **OS**: Linux（systemd を利用する場合は systemd ベースのディストリビューション）
- **Docker**: インストール済みであること（[Install Docker Engine](https://docs.docker.com/engine/install/)）。未導入の場合 `install.sh` は明示エラーで停止する。
- **権限**: root もしくは `sudo`（コンテナ起動・`/etc/beams/` 書き込み・systemd 設置のため）

---

## 2. インストール手順

```bash
# HTTP のみ（TLS 終端は ONCE プラットフォームに委ねる）
RAILS_MASTER_KEY=<config/master.key の値> sudo -E bash deploy/once/install.sh
```

`install.sh` は以下を行う:

1. `docker` コマンドの存在確認（無ければエラー終了）
2. `RAILS_MASTER_KEY` の存在確認（**必須**。未指定ならエラー終了）
3. ホスト env ファイル `/etc/beams/beams.env`（権限 `600`）に `RAILS_MASTER_KEY` / `IMAGE` を書き出し
4. named volume `beams_storage` を作成（冪等）
5. `docker pull "$IMAGE"`
6. 既存 `beams` コンテナがあれば停止・削除し、`docker run -d` で再起動
   （`--name beams --restart unless-stopped -p 80:80 -v beams_storage:/rails/storage --env-file /etc/beams/beams.env "$IMAGE"`）

> **`IMAGE` は未確定**。既定値はプレースホルダ `ghcr.io/REPLACE_ME/beams:latest` であり、**配布時に実レジストリ/タグへ差し替える必要がある**。`install.sh` 冒頭の `IMAGE` 変数（または環境変数 `IMAGE=...`）で指定する。`bin/once-update`（`lib/beams/once/updater.rb`）も同じ既定値を参照するため、両者を同一の値に揃えること。

---

## 3. 環境変数

| 変数 | 必須/任意 | 説明 |
|------|:---:|------|
| `RAILS_MASTER_KEY` | **必須** | `config/master.key` の値。Rails の暗号化資格情報（Active Record Encryption 等）の復号に使う。 |
| `IMAGE` | 任意（既定はプレースホルダ） | 配布イメージ参照。既定 `ghcr.io/REPLACE_ME/beams:latest`。配布時に実値へ差し替える。 |

機密値（`RAILS_MASTER_KEY`）は `docker run -e` ではなく **ホスト env ファイル `/etc/beams/beams.env`（権限 600）経由（`docker run --env-file`）**で渡す。これにより鍵が `ps` などのプロセス一覧に現れず、コンテナ再生成後も同じ env ファイルを再利用できる。

---

## 4. ポート

Beams コンテナは **HTTP 80 のみ**を公開する（`-p 80:80`、Dockerfile も `EXPOSE 80`）。TLS 終端は ONCE プラットフォーム側で行うため、本コンテナ単体では HTTPS を扱わない。

### Thruster 関連 env と既定値

| env | 既定 | 説明 |
|-----|:---:|------|
| `HTTP_PORT` | `80` | Thruster の HTTP 待受ポート。 |
| `TARGET_PORT` | `3000` | Thruster が転送する先（Puma）のポート。 |

通常は既定のままでよい。`install.sh` はポートを `-p 80:80` で固定マッピングしているため、`HTTP_PORT` を変更する場合はコンテナの公開ポートも合わせて調整すること。

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

## 7. 自動アップデート（systemd）

ONCE は自動アップデートを前提とする。ホスト側で daily に最新イメージを pull し、ダイジェストに差分があればコンテナを再生成する。再生成時に `bin/boot` が 4 つの SQLite DB へ `db:prepare` を流すため、**マイグレーションは自動適用**される。

### 設置手順（例）

リポジトリ（または配布物）を `/opt/beams` に配置している前提。

```bash
# 1. unit ファイルを設置
sudo cp deploy/once/once-update.service /etc/systemd/system/
sudo cp deploy/once/once-update.timer   /etc/systemd/system/

# 2. 反映して timer を有効化
sudo systemctl daemon-reload
sudo systemctl enable --now once-update.timer

# 3. 状態確認
systemctl list-timers once-update.timer
systemctl status once-update.service
```

### 調整が必要な箇所

`deploy/once/once-update.service` 内のパスは設置環境に合わせて調整する:

- `ExecStart=/opt/beams/bin/once-update` — `bin/once-update` の実パス
- `WorkingDirectory=/opt/beams`（コメントアウト中。必要なら有効化）

### 挙動

- **`OnCalendar=daily`**（`once-update.timer`）。`Persistent=true` によりホスト停止中に逃した実行を起動時に追いつく。
- **`ExecStartPre`** が更新前に稼働コンテナ内バックアップ（`docker exec beams bundle exec rake beams:backup`）を実行する。
- **バックアップ失敗時はアップデートを中止**する（`ExecStartPre` 失敗で unit が失敗し `ExecStart` は実行されない＝fail-closed / 安全側）。
- `bin/once-update` は `docker pull` 後に**ローカルイメージID（同タグ更新の有無）を比較**し、**同一なら再生成しない**。差分があるときだけコンテナを停止・削除・再 run する（`install.sh` と同一の run 引数）。
- アップデート対象のイメージは env ファイル `/etc/beams/beams.env` の `IMAGE` を尊重する（`once-update.service` が `EnvironmentFile=/etc/beams/beams.env` で読み込む）。そのため `IMAGE` を旧タグに固定したロールバック後も、自動アップデートが `:latest` を pull して巻き戻すことはない。

---

## 8. 手動アップデート / ロールバック

### 手動アップデート

```bash
# ホスト system ruby で直接（bundler 不要）
/opt/beams/bin/once-update

# もしくは install.sh の再実行でも更新できる
RAILS_MASTER_KEY=<key> sudo -E bash deploy/once/install.sh
```

`bin/once-update` は設定イメージと差分が無ければ「already up to date」を表示して何もしない。

### ロールバック

1. `IMAGE` を**以前のタグ**に指定して install.sh を再実行する:

   ```bash
   IMAGE=ghcr.io/REPLACE_ME/beams:<以前のタグ> \
   RAILS_MASTER_KEY=<key> sudo -E bash deploy/once/install.sh
   ```

   再実行で `/etc/beams/beams.env` の `IMAGE` がその旧タグに更新される。自動アップデート（`bin/once-update` / timer）も `EnvironmentFile` 経由でこの `IMAGE` を尊重するため、**ロールバックを巻き戻さない**。永続データは `beams_storage` に残るため、コンテナを差し替えてもデータは保持される。
2. データ自体を以前の状態へ戻す必要がある場合は、バックアップ世代からの復旧（[docs/RESTORE.md](RESTORE.md) の `rake beams:restore[generation]`）を行う。

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

## 9. 関連ドキュメント

- バックアップ・復旧の詳細: [docs/RESTORE.md](RESTORE.md)
- 製品方針・配布形態: [docs/PRODUCT_PLAN.md](PRODUCT_PLAN.md)（§2 配布形態）
- 実装トピック: [docs/tasks/18-once-distribution.md](tasks/18-once-distribution.md)
