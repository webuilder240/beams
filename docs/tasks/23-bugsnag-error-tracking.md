# トピック23: Bugsnag による例外通知

> 本番環境で発生した未捕捉例外（Web リクエスト・バックグラウンドジョブ）を Bugsnag に通知する。
> 計画書には明示されていない運用品質向上トピック。MVP 後の安定運用フェーズの一部として実施する。
> ローカル（development / test）では Bugsnag を無効化し、API キー未設定でも `bundle exec rspec` が落ちないこと。

- **ステータス**: ✅完了（**全決定事項 B1-B4 確定済み 2026-06-06**・実装完了 2026-06-06）
- **依存**: [[03-auth-users]]（ログイン中ユーザー情報を例外イベントに付与するため `current_user` を利用）/ [[02-once-deployment]]（`.kamal/secrets` 経由で `BUGSNAG_API_KEY` を渡す）
- **関連計画書**: 該当なし（運用品質向上）

---

## ボス決定事項（**全項目確定 2026-06-06**）

| ID | 決定内容 |
|---|---|
| **B1** ✅ | **API キーは `ENV["BUGSNAG_API_KEY"]` から取得**。`.kamal/secrets` で渡す前提。Rails credentials や DB には保存しない |
| **B2** ✅ | **通知対象環境は production のみ**。development / test では Bugsnag を無効化し、API キー未設定でも `bundle exec rspec` が落ちないこと（`notify_release_stages` で制御） |
| **B3** ✅ | **バックグラウンドジョブ（Solid Queue / ActiveJob）の例外も Bugsnag で拾う**。Bugsnag gem の Railtie に依存し、明示的に無効化しない |
| **B4** ✅ | **例外通知にログイン中ユーザー情報（`id` と `email_address`）を付与**。`before_bugsnag_notify` コールバックで `current_user` 相当の情報を埋め込む |

### B4 詳細: ユーザー情報の取得経路

本プロジェクトには `Current` 属性モデル（`ActiveSupport::CurrentAttributes` を継承する `app/models/current.rb`）は存在せず、認証は `app/controllers/concerns/authentication.rb` の `current_user` ヘルパで実装されている（`session[:user_id]` から `User` を引く）。

そのため B4 を満たすには次のいずれかが必要:

- **方針 A（採用）**: `ActiveSupport::CurrentAttributes` を継承した `Current` クラス（`app/models/current.rb`）を新設し、`ApplicationController` の `before_action` で `Current.user = current_user` をセットする。Bugsnag コールバックは `Current.user` を参照して `event.set_user(id, email_address)` する。
  - メリット: コントローラとジョブの両方で同じ参照経路になる（ジョブ側に `Current.user` を渡すコードは別途必要だが、まずは Web 例外をカバー）。
  - リクエスト終了時に Rails が自動でリセットするためスレッド汚染なし。
- **方針 B（不採用）**: コントローラ内で直接 `Bugsnag.notify` をラップする。→ 未捕捉例外（500）には適用できないので不可。

**採用は方針 A**。`Current` の最小実装（`attribute :user`）を本トピックで追加する。

### B4 詳細: ジョブにおけるユーザー情報

ActiveJob 内で発生した例外は、`Current.user` がセットされていない可能性が高い。本トピックではジョブ側でのユーザー情報伝播（perform 引数化・job serializer のラップなど）は**スコープ外**とし、ジョブ起因の Bugsnag イベントは `user` 未設定でも問題ないものとする（コンテキスト・ジョブ名・引数は Bugsnag gem の Railtie が自動付与する）。

---

## ゴール（完了の定義）

- production で未捕捉例外が発生すると Bugsnag に通知される
- development / test では Bugsnag が一切ネットワーク通信を行わない（無効化）
- `BUGSNAG_API_KEY` 未設定でも development / test 起動が落ちない（`bin/rails server` / `bundle exec rspec` がエラーにならない）
- production の Web リクエスト例外には `current_user` の `id` と `email_address` が付与される（ログイン中のとき）
- 未ログイン時はユーザー情報なしで通知される（例外を発生させない）
- Solid Queue（ActiveJob）で発生したジョブ例外も Bugsnag に通知される
- RSpec が通り、SimpleCov 85% 以上を維持
- `bin/rubocop` / `bin/brakeman` / `bin/bundler-audit` クリーン

---

## スコープ外（やらないこと）

- Sentry / Rollbar / Honeybadger 等、他の例外通知サービス対応
- フロントエンド JavaScript 例外通知（`bugsnag-js`）
- ソースマップ（minified JS のシンボル化）アップロード
- Bugsnag からの Slack / Email / Webhook 通知連携の設定（Bugsnag ダッシュボード側の設定であり、Beams 側のコードでは扱わない）
- Bugsnag への release / deploy 通知（`bugsnag-release` 等）
- 例外以外のメトリクス送信（Performance Monitoring / Stability Score の能動送信）
- ActiveJob ジョブから `Current.user` を復元する仕組み（job 引数化など）
- 既存例外の握りつぶしポイントを `Bugsnag.notify` で明示通知する作業（必要になったら別トピック）

---

## 前提・参照（実読済み）

- `app/controllers/concerns/authentication.rb` — `current_user` ヘルパ（`session[:user_id]` → `User.find_by(id:)`）。`Current` モデルは存在しない。
- `app/models/user.rb` — `email`（カラム名は `email`。`normalizes :email` で小文字化）。**B4 で要求された属性名 `email_address` は実体としては `User#email` を指す**。Bugsnag のイベントに送信するときも `event.set_user(user.id, user.email)` で送る（ボスの「`email_address`」表現は識別用の意味付けと解釈し、実装上はカラム `email` を使う）。
- `app/controllers/application_controller.rb` — `include Authentication`。Solid Queue / ActiveJob のキューバックエンドは `config/queue.yml`、Solid Queue は `02-once-deployment` 完了済み。
- Bugsnag Ruby gem は Rails 用 Railtie を提供しており、`ActiveJob` を自動で計測する（明示的に disable しない限り）。
- `.kamal/secrets` で本番環境変数を渡す既存パターンを踏襲する（既存の `RAILS_MASTER_KEY` 等と同様）。

---

## タスク

### 仕様確認・調査

- [x] 既存の例外ハンドリング（`ApplicationController` の `rescue_from`、`config/application.rb` の `exceptions_app` 等）を grep して、Bugsnag が干渉しないことを確認する
- [x] Bugsnag gem の最新安定版（Gemfile に追加するバージョン）を確認する
- [x] `Current` モデルの追加方針（B4 詳細・方針 A）でよいか、`ApplicationController` への `before_action` フックの差し込み位置を確認

### Gem 追加

- [x] `Gemfile` の本体 group（テスト/開発限定ではなく production でも有効になる位置）に `bugsnag` を追加
- [x] `bundle install` を実行し、`Gemfile.lock` を更新
  - 受け入れ条件: `bundle install` 成功、`Gemfile.lock` に `bugsnag` のエントリが追加されている

### Current モデル（B4 方針 A）

- [x] `app/models/current.rb` を新規作成（`ActiveSupport::CurrentAttributes` を継承、`attribute :user`）
- [x] `app/controllers/application_controller.rb`（または `Authentication` concern）に `before_action :set_current_user` を追加し、`Current.user = current_user` をセット
  - 受け入れ条件:
    - `spec/models/current_spec.rb` — `Current.user` に `User` をセット/取得できる
    - リクエストスペックで、ログイン中のリクエスト処理中に `Current.user` が `current_user` と一致する（簡易ヘルパスペック）

### Bugsnag 初期化（B1 / B2）

- [x] `config/initializers/bugsnag.rb` を新規作成
  - `Bugsnag.configure do |config|`
    - `config.api_key = ENV["BUGSNAG_API_KEY"]`
    - `config.release_stage = Rails.env`
    - `config.notify_release_stages = %w[production]`（B2: production のみ通知）
    - `config.app_version = ENV["APP_VERSION"]`（任意・存在しなければ nil で可）
    - `config.send_environment = false`（センシティブな ENV 流出防止）
  - 末尾で `before_bugsnag_notify` フック登録（B4）:
    - `Bugsnag.before_notify do |report| ... end` あるいは `add_on_error` 等、利用する gem バージョンの推奨 API を使う
    - `Current.user` を参照し、存在すれば `report.user = { id: Current.user.id, email: Current.user.email }`（または `event.set_user`）。存在しなければ何もしない（例外を発生させない）
  - 受け入れ条件:
    - production 環境で `Bugsnag.configuration.api_key` が `ENV["BUGSNAG_API_KEY"]` と一致する
    - development / test 環境では `Bugsnag.configuration.notify_release_stages` に `Rails.env` が含まれず、`Bugsnag.notify` を呼んでも実 HTTP リクエストが送られない
    - `BUGSNAG_API_KEY` 未設定の状態で `Rails.application.eager_load!` / `bundle exec rspec` が落ちない

### ActiveJob / Solid Queue 例外フック（B3）

- [x] Bugsnag gem の ActiveJob Railtie が有効になっていることを確認（明示的に `config.disable_sidekiq` 等の無効化フラグを立てない）
- [x] Solid Queue を使ったジョブで `raise` した場合に Bugsnag が `notify` 呼び出しを行うことを spec で検証
  - 受け入れ条件:
    - `spec/jobs/bugsnag_integration_spec.rb` でダミージョブを `perform_now` で実行し、例外時に `Bugsnag.notify` 相当が呼ばれることを stub で確認

### ユーザー情報付与（B4）コールバック動作テスト

- [x] `spec/initializers/bugsnag_spec.rb`（または `spec/lib/bugsnag_notify_spec.rb` 相当） — `Bugsnag` を stub し、`Current.user` がセットされている状態で `Bugsnag.notify` を呼ぶと、event の `user` に `id` / `email` が含まれることを検証
- [x] `Current.user` が nil のとき、event に user 情報が付かず例外が発生しないことを検証

### RSpec 全体

- [x] `bundle exec rspec` が green、SimpleCov 85% 以上を維持
- [x] 既存テストを壊していない
- [x] テスト実行中に Bugsnag への実 HTTP リクエストが送られない（WebMock などで一応ブロックされていることを確認。`config.notify_release_stages` の設定で十分なはず）

### Lint・セキュリティ

- [x] `bin/rubocop` クリーン
- [x] `bin/brakeman --no-pager` クリーン
- [x] `bin/bundler-audit` クリーン

### ドキュメント

- [x] `README.md`（または環境変数を列挙している既存ドキュメント）に `BUGSNAG_API_KEY` の設定方法を追記
  - 例: production で `.kamal/secrets` から渡す手順 / development では未設定で動く旨
- [x] `docs/tasks/00-overview.md` のトピック表に「23: Bugsnag による例外通知」を追加（ステータス: 未着手）
- [x] `docs/tasks/PROGRESS_LOG.md` のサマリ表に行 23 を追加（ステータス: 未着手）
- [x] `docs/tasks/progress/23-bugsnag-error-tracking.md` を新規作成し、時系列ログ用の空ファイルとして用意（Coder が作業時に追記する）
- [ ] `docs/tasks/manager/23-bugsnag-error-tracking.md` も同様に空ファイルとしてマネージャーが用意（本トピックでは Coder 側では touch せず、`/agent-team` 着手時にマネージャーが作成）

---

## 動作確認（マネージャー検証用・受け入れ条件）

- [x] development で `BUGSNAG_API_KEY` 未設定のまま `bin/rails server` 起動 → エラーなく起動する
- [x] test 環境で `BUGSNAG_API_KEY` 未設定のまま `bundle exec rspec` 全 green、Bugsnag への実通信ゼロ
- [ ] production 相当の環境（`RAILS_ENV=production` + `BUGSNAG_API_KEY` 設定）でわざと未捕捉例外を発生させると Bugsnag ダッシュボードに event が登録される（手動確認、または `Bugsnag.notify` 直接呼び出しで代替）
- [x] その event に user.id と user.email が含まれている（ログイン中のリクエスト由来である場合）
- [x] Solid Queue ジョブ内の `raise` も Bugsnag に通知される
- [x] `bundle exec rspec` 全 green、SimpleCov 85% 以上
- [x] `bin/rubocop` / `bin/brakeman` / `bin/bundler-audit` クリーン

---

## 参考リンク

- Bugsnag Ruby on Rails 公式ドキュメント: https://docs.bugsnag.com/platforms/ruby/rails/

---

## 未決事項・質問

なし（B1〜B4 はすべて確定済み 2026-06-06）。
