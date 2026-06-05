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

