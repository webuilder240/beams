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
once install \
  --image ghcr.io/webuilder240/beams:latest \
  --env RAILS_MASTER_KEY=<config/master.key の値>
```

## 環境変数

| 変数 | 必須 | 用途 |
| --- | --- | --- |
| `RAILS_MASTER_KEY` | 必須 | `config/master.key` の値。Active Record Encryption（BigQuery SA 鍵など）の復号に使う。ONCE の custom env（TUI または `once install --env KEY=VALUE`）で渡す。 |
| `BUGSNAG_API_KEY` | production のみ | Bugsnag への例外通知用 API キー。ONCE の custom env または `once install --env BUGSNAG_API_KEY=...` で渡す。development / test では未設定で問題なく、Bugsnag への実通信は行われない（`config/initializers/bugsnag.rb` で `enabled_release_stages = %w[production]` にしているため）。 |
| `APP_VERSION` | 任意 | Bugsnag のイベントに付与するアプリバージョン。未設定でも動作に影響なし。 |

`SECRET_KEY_BASE` は ONCE が初回インストール時に自動生成・保持するため、ユーザーが渡す必要はない。
