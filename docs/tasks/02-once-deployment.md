# トピック02: ONCE配布・プロセス管理

> 単一 Docker コンテナで port 80 待受・`/storage` 永続化・自前スーパーバイザ `bin/boot` による Procfile ベースのプロセス管理を実装し、ONCE 配布形態に対応する。計画書 §2 / §2.1 / §2.2 / §6.5 に対応。

- **ステータス**: 完了
- **依存**: [[01-foundation-rename]]（モジュール名が `Beams` に確定し、`bundle exec rspec` / `bin/rubocop` が通る土台）
- **関連計画書**: §2, §2.1, §2.2, §6.5

## ゴール（完了の定義）

- `bin/boot` が存在し、`Procfile` を読み込んで `web` と `worker` の両プロセスを `Process.spawn` で起動できる
- `Procfile` に `web`（Thruster ラップ）と `worker`（SolidQueue）が定義されている
- `Dockerfile` の `CMD` が `bin/boot` 一発になっている
- コンテナ起動時に 4DB（primary / cache / queue / cable）すべてへ `db:prepare` が実行される（`bin/boot` 内または起動ステップで）
- `bin/boot` が `INT` / `TERM` / `CLD` シグナルをトラップし、子プロセスへ伝播して全プロセスを `wait` で回収する
- `http://localhost:80/up` が 200 を返す（コンテナ内での動作確認）
- `bin/rubocop` がエラーなし（`bin/boot` の Ruby コードを含む）
- `bundle exec rspec` が引き続き通る（既存 spec を壊さない）

## 前提・参照

- `Dockerfile` — 現在の `CMD` は `["./bin/thrust", "./bin/rails", "server"]`。`ENTRYPOINT` は `bin/docker-entrypoint`（現在は `web` 起動時のみ `db:prepare` を実行する簡易スクリプト）
- `bin/docker-entrypoint` — 現状は `db:prepare` を1DB のみ対象に実行している（production では4DB対応が必要）
- `bin/thrust` — Thruster バイナリラッパーとして既存
- `bin/jobs` — SolidQueue worker 起動スクリプトとして既存
- [once-campfire の `bin/boot`](https://github.com/basecamp/once-campfire) — 約50行の Ruby 自前スーパーバイザ。INT/TERM/CLD トラップ、`Process.spawn`、`Process.wait` ループ。このコードを**翻訳して流用**する（ライセンス確認も行うこと）
- 計画書 §2.2 の Procfile 定義:
  ```
  web:    bundle exec thrust bin/rails server
  worker: bundle exec bin/jobs
  ```
- 計画書 §6.5 — 起動時に4DB全てへ `db:prepare` を流す（`bin/boot` 固有の追加処理）

## タスク

### Procfile 作成

- [x] プロジェクトルートに `Procfile` を新規作成し、`web` と `worker` の2エントリを計画書 §2.2 の定義通りに記述する (`Procfile`)
  - 受け入れ条件: `cat Procfile` で `web:` と `worker:` の両行が確認できる
  - 受け入れ条件: `web` は `bundle exec thrust bin/rails server`、`worker` は `bundle exec bin/jobs`

### bin/boot 実装

- [x] `bin/boot` を新規作成する（Ruby スクリプト、shebang `#!/usr/bin/env ruby`）。once-campfire の実装を参考に以下を実装する: `Procfile` 読み込み → 各コマンドを `Process.spawn` で起動 → 子 PID リストを保持 → `INT/TERM` トラップで全子プロセスに同シグナルを伝播 → `CLD`（SIGCHLD）または `loop { Process.wait }` で全子プロセスを wait (`bin/boot`)
  - 受け入れ条件: `chmod +x bin/boot` 済みで、`bin/boot` を実行すると `Procfile` の全プロセスが起動する
  - 受け入れ条件: Ctrl-C（SIGINT）を送ると全子プロセスが終了してスーパーバイザも終了する
  - 未決: once-campfire の `bin/boot` のライセンスを確認し、流用可否・著作権表記要否を判断すること
- [x] `bin/boot` 内で `web` プロセス起動前に 4DB すべてへ `db:prepare` を実行するステップを追加する (`bin/boot`)
  - 受け入れ条件: `bin/boot` 起動時のログに4DB分の migrate/prepare 出力が現れる（またはすでに最新なら「already up to date」相当のメッセージ）
  - 受け入れ条件: primary / cache / queue / cable の4DBに対して `DATABASE_URL` または `db:prepare` タスクが適切に呼ばれる（`rails db:prepare` だけでは4DB全て対象か確認が必要）

### Dockerfile 更新

- [x] `Dockerfile` の `CMD` を `["bin/boot"]` に変更する (`Dockerfile`)
  - 受け入れ条件: `docker inspect <image>` または Dockerfile 末尾の `CMD` が `["bin/boot"]` になっている
- [x] `Dockerfile` の `ENTRYPOINT`（`bin/docker-entrypoint`）が `bin/boot` と役割が重複しないよう整理する。`bin/boot` 側で `db:prepare` を担う場合、`docker-entrypoint` の `db:prepare` 呼び出しは削除または無効化する (`bin/docker-entrypoint`, `Dockerfile`)
  - 受け入れ条件: コンテナ起動時に `db:prepare` が二重実行されない
  - 未決: `ENTRYPOINT` 自体を残すか `CMD` のみにするかは once-campfire の構成を確認して判断する

### ヘルスチェック確認

- [x] `config/routes.rb` または Rails 8 デフォルトで `/up` エンドポイントが定義されていることを確認する (`config/routes.rb`)
  - 受け入れ条件: `bin/rails routes | grep up` に `/up` エンドポイントが表示される
  - 受け入れ条件: `curl -s -o /dev/null -w "%{http_code}" http://localhost:80/up` がコンテナ起動後に `200` を返す（手動確認）

### 永続化パス確認

- [x] `config/database.yml` の production 全DBが `/storage` 配下を向いていることを再確認し、`Dockerfile` で `/storage` がボリュームマウントポイントとして `VOLUME` 宣言または外部マウント前提になっているか確認する (`Dockerfile`, `config/database.yml`)
  - 受け入れ条件: production の全 SQLite パスが `storage/` 相対パス（コンテナ内では `/rails/storage/`）になっている
  - 受け入れ条件: `config/storage.yml` の `local` サービスも `storage/` を向いている

### Lint・テスト

- [x] `bin/rubocop` を実行し、`bin/boot` の Ruby コードが RuboCop ルール（`rubocop-rails-omakase`）に準拠していることを確認、違反があれば修正する (`bin/boot`)
  - 受け入れ条件: `bin/rubocop bin/boot` が exit code 0（または rubocop が bin/ を対象にしている場合はそれに従う）
- [x] `bundle exec rspec` を実行し、このトピックの変更で既存 spec が壊れていないことを確認する (`spec/`)
  - 受け入れ条件: exit code 0、SimpleCov カバレッジ 85% 以上（[[01-foundation-rename]] 完了後の状態が前提）

## 動作確認

- [ ] `bin/boot` を直接実行し、`web` と `worker` の両プロセスが起動することをログで確認する（手動確認）
- [ ] Ctrl-C でシグナルを送り、全プロセスが正常終了することを確認する（手動確認）
- [ ] Docker イメージをビルドし（`docker build -t beams .`）、`docker run -d -p 80:80 -e RAILS_MASTER_KEY=<key> -v $(pwd)/storage:/rails/storage beams` でコンテナを起動する（手動確認）
- [ ] `curl http://localhost:80/up` が `{"status":"ok"}` 相当の 200 レスポンスを返す（手動確認）
- [ ] コンテナログに4DB分の `db:prepare` 実行ログが表示されている（手動確認）
- [ ] コンテナを再起動した場合も `db:prepare` が冪等に（エラーなしで）実行される（手動確認）

## 未決事項・質問

- once-campfire の `bin/boot` のライセンス（MIT 等）確認が必要。コードを翻訳流用する場合の著作権表記要否を確認すること。
- `rails db:prepare` を4DB全てに適用するコマンドの正確な形式（`rails db:prepare` は `DATABASE_URL` 環境変数なしでも `database.yml` の全 DB を対象にするか、それとも `rails db:prepare:cache db:prepare:queue db:prepare:cable` のように個別タスクが必要か）を実際に確認すること。
- `ENTRYPOINT` の `bin/docker-entrypoint` を完全に廃止するか、非 ONCE 用途（Kamal デプロイ）向けに残すかの方針を決める必要がある。
- `bin/boot` が `Procfile` から起動する際の環境変数（`RAILS_ENV=production` 等）の引き継ぎ方法を確認すること。
- Thruster が port 80 で待受けるための設定（`THRUSTER_PORT=80` または `bin/thrust` のオプション）が必要か確認すること。
