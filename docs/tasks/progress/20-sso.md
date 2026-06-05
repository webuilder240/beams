# トピック20 実装ログ: SSO（Google OAuth ログイン）

## 実装日時
2026-06-06 開始

## ブランチ
`feat/20-sso`（worktree: `.claude/worktrees/feat-20-sso/`）

## 設計方針

- `users` テーブルには認証方式（password/oauth）カラムを増やさない
- パスワード認証は `password_credentials` テーブル、OAuth identity は `oauth_identities` テーブルに分離
- `User#password=` / `#authenticate` は仮想属性 + 委譲で従来の API を保つ
- マイグレーション内で既存 `users.password_digest` を `password_credentials` に全件コピーしてからカラムを削除

## ボス確定事項（B1〜B9 — 2026-06-06）

20-sso.md 表参照。すべて推奨案で確定済み。

## 時系列ログ

### Phase 0: 前提確認（2026-06-06）

- worktree `feat/20-sso`、ベース `58a8cb4`
- 既存テスト（非 system）434 examples / 0 failures / 98.68% line coverage を確認（tailwindcss:build 後）
- `users.password_digest NOT NULL` を含む現行スキーマを確認
- 既存のパスワード関連呼び出し箇所:
  - `SessionsController#create` → `user&.authenticate(params[:password])`
  - `Admin::UsersController#create` → `user_params` で `:password` を許可
  - `Admin::UsersController#reset_password` → `user.update(password: new_password)`
  - `SetupWizardController#create_step1` → `step1_params` で `:password`, `:password_confirmation`

### Phase 1: gem 追加 + OmniAuth initializer

- `Gemfile` に `omniauth` / `omniauth-google-oauth2` / `omniauth-rails_csrf_protection` を追加
- `bundle install` 成功（`omniauth-2.1.4`, `omniauth-google-oauth2-1.2.2`, `omniauth-rails_csrf_protection-2.0.1`）
- `bin/bundler-audit` クリーン
- `config/initializers/omniauth.rb` を作成 — `GOOGLE_OAUTH_CLIENT_ID/SECRET` 揃った時のみ provider 登録（ENV 未設定でも起動成功）

### Phase 2: マイグレーション

- 事前バックアップ: `storage/development.sqlite3.bak-20-sso`
- 検証用ユーザー `predev@example.com / secret123` を開発DBに登録（事前）
- `db/migrate/20260606000001_create_password_credentials_and_migrate.rb`（テーブル作成 + データ移行 + `users.password_digest` 削除）
- `db/migrate/20260606000002_create_oauth_identities.rb`
- `db/migrate/20260606000003_add_allowed_email_domain_to_application_settings.rb`
- `bin/rails db:migrate` 成功 → `Migrated 1 / 1 user password_digests`
- 開発DB で `BCrypt::Password.new(pc.password_digest).is_password?("secret123") == true` を確認
- `bin/rails db:rollback STEP=3` 成功 → `users.password_digest` 復元と bcrypt 一致を確認
- 再度 `bin/rails db:migrate` で前進
- `bin/rails db:test:prepare` 成功
- `db/schema.rb` に `password_credentials`・`oauth_identities`・`application_settings.allowed_email_domain` 反映、`users.password_digest` 消失を確認

### Phase 3: 識別子モデル + User モデル改修

- `PasswordCredential` モデル（belongs_to :user, has_secure_password, validates :user_id uniqueness）
- `OauthIdentity` モデル（belongs_to :user, presence + (provider, uid) uniqueness, `for` スコープ）
- `User` モデルから `has_secure_password` を削除、`attr_accessor :password, :password_confirmation`、`after_save :sync_password_credential`、`authenticate` を委譲、`find_or_create_for_oauth` 追加
- `User.allowed_oauth_email?` ヘルパで `ApplicationSetting#allowed_email_domain` の判定
- `find_or_create_for_oauth` 4 分岐の RSpec 追加 + 既存 `user_spec` 全パス
- 非 system 全体スイート 455 examples / 0 failures（フル運用前のチェックポイント）

