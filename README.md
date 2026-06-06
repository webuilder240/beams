# README

Beams は BigQuery 専用 BI ツール（Redash 後継）。ONCE プラットフォーム（[basecamp/once](https://github.com/basecamp/once)）で配布する。

## 配布イメージ

公式イメージは GitHub Container Registry で公開している:

```
ghcr.io/webuilder240/beams:latest
```

`main` への push ごとに `:latest` および `:<git-sha>` の 2 タグが multi-arch（`linux/amd64` / `linux/arm64`）でビルド・公開される（[.github/workflows/release.yml](.github/workflows/release.yml)）。

## インストール

ONCE CLI / TUI 経由で 1 コマンド設置する。詳細手順は [docs/INSTALL.md](docs/INSTALL.md) を参照。

```bash
curl https://get.once.com | sh        # ONCE CLI を導入
once install --image ghcr.io/webuilder240/beams:latest
```

## 環境変数

| 変数 | 必須 | 用途 |
| --- | --- | --- |
| `BUGSNAG_API_KEY` | production のみ | Bugsnag への例外通知用 API キー。ONCE の custom env または `once install --env BUGSNAG_API_KEY=...` で渡す。development / test では未設定で問題なく、Bugsnag への実通信は行われない（`config/initializers/bugsnag.rb` で `enabled_release_stages = %w[production]` にしているため）。 |
| `APP_VERSION` | 任意 | Bugsnag のイベントに付与するアプリバージョン。未設定でも動作に影響なし。 |

`SECRET_KEY_BASE` は ONCE が初回インストール時に自動生成・永続化するため、ユーザーが渡す必要はない。`RAILS_MASTER_KEY` も**不要**（Beams は `config/credentials.yml.enc` を持たない。詳細は [docs/adr/0002-drop-active-record-encryption.md](docs/adr/0002-drop-active-record-encryption.md)）。

## セキュリティ

BigQuery サービスアカウント JSON 鍵は SQLite に**平文**で保存される。バックアップファイル（`/storage/backups/*.sqlite3.gz`）も平文。ホスト側のディスク暗号化・ファイルパーミッション・バックアップ転送経路の暗号化で守ること。詳細は [docs/INSTALL.md §3 セキュリティ上の注意](docs/INSTALL.md) を参照。
