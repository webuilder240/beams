# トピック18: KamalからONCE配信への移行

> 既存の Kamal デプロイ基盤を完全撤去し、ONCE（買い切り・自社サーバー単一コンテナ）として配信できる状態にする。コンテナ内のプロセス管理（`bin/boot`・`Procfile`・`/storage`・`/up`・port 80・起動時 `db:prepare`）は[[02-once-deployment]]で実装済みのため、本トピックは**配布レイヤ**（Kamal撤去・TLS自動証明・インストーラ・自動アップデート・手順書）を整備する。計画書 §2 に対応。

- **ステータス**: 未着手
- **依存**: [[02-once-deployment]]（`bin/boot` スーパーバイザ・`Procfile`・`/storage` 永続化が前提）, [[15-backup-restore]]（自動アップデート前の `/storage` バックアップ前提）
- **関連計画書**: §2, §2.1, §2.2
- **ユーザー決定（2026-05-31）**:
  - Kamal関連成果物は **完全撤去**（`config/deploy.yml`・`bin/kamal`・`.kamal/`・`Gemfile` の `gem "kamal"`）
  - 配布物の範囲は **インストーラ＋手順書＋TLS自動証明＋自動アップデート** まで

## ゴール（完了の定義）

- リポジトリから Kamal の痕跡が消えている（`grep -ri kamal` がコード/設定/Gemfile に残らない。`docs/tasks/` の履歴記述は除く）
- `Gemfile` / `Gemfile.lock` から `kamal` gem が外れ、`bundle install` が成功し `bundle exec rspec` が通る
- `TLS_DOMAIN` を指定したコンテナ起動で Thruster が 443 で HTTPS 終端し、未指定なら従来どおり port 80 のみで動く（dev/test に影響なし）
- 顧客がまっさらなサーバーで実行できる **インストーラ**（シェル）が `deploy/once/` に存在する
- **自動アップデート**の仕組み（`lib/beams/` の Ruby モジュール＋`bin` ラッパー＋systemd timer テンプレート）が存在し、Ruby ロジックは RSpec でカバーされる
- 配布・運用手順を記した **`docs/INSTALL.md`** が存在し、`CLAUDE.md` のデプロイ節が ONCE を指す
- `bin/rubocop` エラーなし、`bundle exec rspec` green、SimpleCov カバレッジ 85% 以上を維持

---

## A. Kamal 撤去

- [x] `config/deploy.yml` を削除する (`config/deploy.yml`)
  - 受け入れ条件: ファイルが存在しない
- [x] `bin/kamal` を削除する (`bin/kamal`)
  - 受け入れ条件: ファイルが存在しない
- [x] `.kamal/`（`hooks/` の各 `*.sample`・`secrets`）を削除する (`.kamal/`)
  - 受け入れ条件: ディレクトリが存在しない
- [x] `Gemfile` から `gem "kamal", require: false` とその直上のコメント行を削除し、`bundle install` で `Gemfile.lock` を再生成する (`Gemfile`, `Gemfile.lock`)
  - 受け入れ条件: `Gemfile.lock` に `kamal` が現れない
  - 受け入れ条件: `bundle install` が成功し、`bundle exec rspec` が引き続き green
- [x] `Dockerfile` 冒頭コメントの "Use with Kamal" を ONCE 配布前提の記述に書き換える (`Dockerfile`)
  - 受け入れ条件: Dockerfile に "Kamal" の語が残らない
- [x] `.dockerignore` の Kamal 関連無視設定（`/config/deploy*.yml`・`/.kamal`）を削除または ONCE 向けに整理する (`.dockerignore`)
  - 受け入れ条件: 撤去済みパスを参照する無視行が残らない
- [x] `CLAUDE.md` のデプロイ節（「Kamal を使用。`config/deploy.yml` を参照。」）を ONCE 配布（`docs/INSTALL.md` 参照）に更新する (`CLAUDE.md`)
  - 受け入れ条件: 当該節が ONCE を指し、`docs/INSTALL.md` へリンクしている
- [x] `docs/PRODUCT_PLAN.md` の技術スタック表「ONCE（Docker / Kamalベース）」を Kamal 非依存の記述に更新する (`docs/PRODUCT_PLAN.md`)
  - 受け入れ条件: 当該行に "Kamalベース" が残らない
- [x] 全体の Kamal 参照を再確認する
  - 受け入れ条件: `grep -rniE "kamal" . --exclude-dir=.git`（`docs/tasks/` 配下の履歴記述を除く）が 0 件

## B. TLS 自動証明（Thruster）

> Thruster は `TLS_DOMAIN` を与えると Let's Encrypt で証明書を自動取得し HTTPS(443) 終端＋HTTP(80) リダイレクトを行う。未指定なら HTTP(80) のみ。

- [x] `Dockerfile` に `EXPOSE 443` を追加し、80/443 両待受であることを明示する (`Dockerfile`)
  - 受け入れ条件: Dockerfile に `EXPOSE 80` と `EXPOSE 443` の両方がある
- [x] `config/environments/production.rb` で TLS 終端越し運用を有効化する。`TLS_DOMAIN` が設定されているときのみ `config.assume_ssl = true` / `config.force_ssl = true` を有効にし、`/up` を https リダイレクト除外にする (`config/environments/production.rb`)
  - 受け入れ条件: **TDD**。`TLS_DOMAIN` 設定時に通常パスが https へリダイレクトされ、`/up` は除外されることを検証する request spec を先に書く（Red→Green）
  - 受け入れ条件: `TLS_DOMAIN` 未設定時は従来どおり（リダイレクトなし）。dev/test の挙動は不変
  - 未決: production 設定の spec 化方法（`Rails.application.config` 直接検証 or `ssl_options` のラムダ検証）。Coder が最小で検証可能な形を選び、判断を progress に記録
- [ ] Thruster のポート/ドメイン関連 env（`TLS_DOMAIN`・`HTTP_PORT`・`HTTPS_PORT`・`TARGET_PORT`）の挙動と既定値を `docs/INSTALL.md`（後述 E）に整理する
  - 受け入れ条件: `TLS_DOMAIN` 設定有無での待受ポート差が明記されている

## C. インストーラ（シェル）

> まっさらな Linux サーバーで顧客が 1 コマンド実行する想定。Ruby/bundle 非依存の standalone シェル（SimpleCov 計測対象外＝Reviewer/手動で受け入れ確認）。

- [x] `deploy/once/install.sh` を新規作成する。Docker 導入確認→`/storage` 用 named volume 作成→ホスト env ファイル（`/etc/beams/beams.env`、`RAILS_MASTER_KEY`・`TLS_DOMAIN`・`IMAGE` を記録）作成→イメージ pull→`docker run`（`--restart unless-stopped` / `-p 80:80` / `-p 443:443` / `-v <volume>:/rails/storage` / `--env-file /etc/beams/beams.env`）でコンテナ起動、までを行う (`deploy/once/install.sh`)
  - 受け入れ条件: `bash -n deploy/once/install.sh`（構文チェック）が通る。`chmod +x` 済み
  - 受け入れ条件: `RAILS_MASTER_KEY` 未指定時は明示エラーで停止する。`TLS_DOMAIN` 未指定でも HTTP のみで起動できる
  - 受け入れ条件: イメージ参照(`IMAGE`)・コンテナ名・ボリューム名・env ファイルパスを冒頭の変数で一元管理している。`IMAGE` 既定値はプレースホルダ（`ghcr.io/REPLACE_ME/beams:latest`）
  - 受け入れ条件: 鍵は `docker run -e` ではなく env ファイル経由（プロセス一覧に出さない）

## D. 自動アップデート（Ruby モジュール＋ラッパー＋timer）

> ONCE は自動アップデートする。ホスト側で定期的に最新イメージを pull しコンテナを再生成する。再生成時に `bin/boot` が 4DB へ `db:prepare` を流すため、マイグレーションは自動適用される（[[02-once-deployment]]）。ドメインロジックは backup/restore と同じく `lib/beams/` モジュール＋`bin` ラッパー＋`spec/lib` で実装する（service クラス禁止）。

- [x] `lib/beams/once/updater.rb` を新規作成する。`docker pull` で最新イメージ取得→現行/最新イメージダイジェスト比較→差分があればコンテナを停止・削除・再 `run`（install.sh と同じ run 引数＝`--env-file /etc/beams/beams.env` 等）する Ruby モジュール。シェル実行は注入可能な runner（依存性注入）にしてテスト可能にする (`lib/beams/once/updater.rb`)
  - 受け入れ条件: **TDD**。runner をスタブして「最新と同一なら再生成しない」「差分があれば pull→再生成コマンドを正しい引数で発行する」を検証する spec を先に書く (`spec/lib/beams/once/updater_spec.rb`)
  - 受け入れ条件: イメージ参照(`IMAGE`)・コンテナ名・ボリューム名・ポート・env ファイルが install.sh と矛盾しない
- [x] `bin/once-update` 薄いラッパーを新規作成する（`Beams::Once::Updater` を呼ぶ。ホストの system ruby で動くよう stdlib のみ依存） (`bin/once-update`)
  - 受け入れ条件: `ruby -c bin/once-update` が通り、`chmod +x` 済み
- [x] `deploy/once/once-update.service` と `deploy/once/once-update.timer` の systemd テンプレートを新規作成する（定期的に `bin/once-update` を実行） (`deploy/once/once-update.service`, `deploy/once/once-update.timer`)
  - 受け入れ条件: timer は `OnCalendar=daily`。service は `ExecStartPre` で稼働コンテナ内バックアップ（`docker exec <container> rake beams:backup` 相当）を実行してから `ExecStart` で `bin/once-update` を起動する Unit になっている
  - 受け入れ条件: バックアップ失敗時の扱い（更新を止めるか続行するか）を Unit のコメントに明記する

## E. 配布・運用手順書

- [ ] `docs/INSTALL.md` を新規作成する。前提（Linux + Docker）/ `install.sh` の使い方 / 必須 env（`RAILS_MASTER_KEY`・`TLS_DOMAIN`）/ ポート(80,443) / `/storage` ボリュームとバックアップ（[docs/RESTORE.md](../RESTORE.md) へリンク）/ 自動アップデート（systemd timer 設置手順）/ 手動アップデート・ロールバック、を記載する (`docs/INSTALL.md`)
  - 受け入れ条件: 上記項目がすべて含まれ、コマンド例が実在の成果物（`deploy/once/` 配下・`bin/once-update`）と一致する
- [ ] `docs/PRODUCT_PLAN.md` / `00-overview.md` / `PROGRESS_LOG.md` の索引・進捗にトピック18を反映する（マネージャーが完了化時に更新）

## F. Lint・テスト

- [ ] `bin/rubocop` を実行し、追加した Ruby（`lib/beams/once/updater.rb`・`bin/once-update`）が `rubocop-rails-omakase` に準拠することを確認 (`lib/`, `bin/`)
  - 受け入れ条件: `bin/rubocop` が exit code 0
- [ ] `bin/rails db:test:prepare` 後 `bundle exec rspec` を実行し、既存 spec を壊していないこと・カバレッジ 85% 以上を確認 (`spec/`)
  - 受け入れ条件: exit code 0、SimpleCov 85% 以上

## 動作確認（手動）

- [ ] `TLS_DOMAIN` 未指定でイメージをビルド→`docker run -p 80:80 ...` し `curl http://localhost:80/up` が 200（手動）
- [ ] `deploy/once/install.sh` を構文・ドライランで確認（手動）
- [ ] `bin/once-update` を runner スタブ相当（dry-run）で確認（手動）
- [ ] systemd timer テンプレートが `systemd-analyze verify`（可能なら）でエラーなし（手動）

## 未決事項・質問（→ 2026-05-31 ユーザー決定済み）

1. **配布イメージのレジストリ／タグ**: 未確定 → **プレースホルダ変数 `IMAGE` で保留**（既定値例 `ghcr.io/REPLACE_ME/beams:latest`）。install.sh・updater・env ファイル・INSTALL.md がこの 1 変数を参照し、確定後に差し替え可能にする。
2. **自動アップデート前のバックアップ**: → **実行する**。`once-update.service` の `ExecStartPre` で `rake beams:backup` 相当（コンテナ内 `docker exec` で実行）を挟む。[[15-backup-restore]] 連携。
3. **`RAILS_MASTER_KEY` の受け渡し**: → **ホスト env ファイル方式**（例 `/etc/beams/beams.env`）。`install.sh` が `RAILS_MASTER_KEY`・`TLS_DOMAIN`・`IMAGE` を env ファイルに書き出し、`docker run --env-file` と `bin/once-update`/`Beams::Once::Updater` が共通参照する。鍵がプロセス一覧に出ず、コンテナ再生成後も再利用できる。INSTALL.md に手順を明記。
4. **アップデート間隔**: → **daily 固定**（カスタマイズ不要）。`once-update.timer` に `OnCalendar=daily` を設定。
