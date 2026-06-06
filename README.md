# README

Beams は BigQuery 専用 BI ツール（Redash 後継）。ONCE プラットフォーム（basecamp/once）で配布する。

## 配布イメージ

公式イメージは GitHub Container Registry で公開している:

```
ghcr.io/webuilder240/beams:latest
```

`main` への push ごとに `:latest` および `:<git-sha>` の 2 タグが multi-arch（`linux/amd64` / `linux/arm64`）でビルド・公開される（[.github/workflows/release.yml](.github/workflows/release.yml)）。インストール手順は [docs/INSTALL.md](docs/INSTALL.md) を参照。

This README would normally document whatever steps are necessary to get the
application up and running.

Things you may want to cover:

* Ruby version

* System dependencies

* Configuration

* Database creation

* Database initialization

* How to run the test suite

* Services (job queues, cache servers, search engines, etc.)

* Deployment instructions

* ...

## 環境変数

| 変数 | 必須 | 用途 |
| --- | --- | --- |
| `BUGSNAG_API_KEY` | production のみ | Bugsnag への例外通知用 API キー。`.kamal/secrets` 経由で渡す。development / test では未設定で問題なく、Bugsnag への実通信は行われない（`config/initializers/bugsnag.rb` で `enabled_release_stages = %w[production]` にしているため）。 |
| `APP_VERSION` | 任意 | Bugsnag のイベントに付与するアプリバージョン。未設定でも動作に影響なし。 |
