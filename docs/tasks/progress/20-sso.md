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

### Phase 4: ApplicationSetting 拡張

- `ApplicationSetting` に `DOMAIN_FORMAT` 正規表現を導入し `allowed_email_domain` を `allow_blank: true` で簡易フォーマット検証
- `spec/models/application_setting_spec.rb` に 6 ケース（空可、単純ドメイン、多段ドメイン、`@` 付きを弾く、空白を弾く、ドットなしを弾く）追加

### Phase 5: OmniAuth コールバック + ルーティング + ビュー

- `spec/support/omniauth.rb` でテストモード有効化 + `mock_oauth_response!` / `mock_oauth_failure!` / `reset_oauth_mocks!` ヘルパ
- `app/controllers/auth/omniauth_callbacks_controller.rb` 新規 — `google_oauth2`（コールバック）/ `failure`（失敗）/ `passthru`（フォールバック）
- `config/routes.rb` に `match "/auth/:provider"` / `get "/auth/google_oauth2/callback"` / `get "/auth/failure"` を追加
- `config/initializers/omniauth.rb` をテストモード対応に拡張（test 環境では実 ENV 不要でダミー provider 登録、本番は ENV 設定時のみ）
- `spec/requests/auth/omniauth_callbacks_spec.rb`: 既存 email リンク / 自動作成 / 拒否 / failure の 4 ケース

### Phase 6: ログイン画面ボタン + admin 設定 UI

- `app/views/sessions/new.html.erb` に `ENV["GOOGLE_OAUTH_CLIENT_ID"].present?` ガード付き `button_to "/auth/google_oauth2"` を追加
- `Admin::SettingsController#setting_params` に `:allowed_email_domain` を追加
- `app/views/admin/settings/edit.html.erb` を「アプリ全体設定」に再構成（コスト単価 / SSO の 2 セクション）
- `spec/system/sso_spec.rb` 3 ケース（ENV 未設定でボタン非表示 / ENV 設定でボタン表示 / mock 経由で実 Google 通信なしログイン成功）
- `spec/requests/admin/settings_spec.rb` に `allowed_email_domain` の更新成功・形式 NG ケースを追加

### Phase 7: ドキュメント

- `docs/PRODUCT_PLAN.md` §7 SSO 行に「実装済み（トピック20）」注記
- `docs/adr/0002-identity-table-separation.md` 新規 — 採用理由・トレードオフ・代替案

## 最終結果

- `bundle exec rspec` 全 549 examples / 0 failures
- SimpleCov Line Coverage 98.87% (1047 / 1059)
- `bin/rubocop` クリーン
- `bin/brakeman --no-pager` Security Warnings: 0
- `bin/bundler-audit` No vulnerabilities found

## 既存ユーザーログイン手動確認（開発DB）

1. マイグレーション前に `User.create!(email: 'predev@example.com', password: 'secret123', role: 'admin')` を seed
2. `storage/development.sqlite3.bak-20-sso` にバックアップ
3. `bin/rails db:migrate` で 3 マイグレーション成功
4. `BCrypt::Password.new(password_credentials.password_digest).is_password?('secret123') == true` を確認
5. `bin/rails db:rollback STEP=3` 後 `users.password_digest` 復元と bcrypt 一致を確認 → 再度 `db:migrate` で前進

## Reviewer 指摘リファクタの対応記録（2026-06-06）

ユーザー承認済みの must + should 全件に対応。

| finding | 内容 | コミット |
|---------|------|----------|
| A | `after_save` の条件を `password_needs_sync?` メソッド化して意図を明示 | `7305f66` |
| B | `find_or_create_for_oauth` の identity 紐付けを `find_or_create_by!` で冪等化 | `7305f66` |
| C | `find_or_create_for_oauth` 全体を `transaction` で囲み内側 transaction を削除 | `7305f66` |
| J | `password_confirmation` の空文字も PC へ伝搬（明示空 = 不一致でエラー） | `7305f66` |
| M | `find_or_create_for_oauth` 先頭で email blank ガード → `nil` を返す | `7305f66` |
| R | 仮想属性 reset を廃し `@password_pending_sync` フラグで再 save 防止 | `7305f66` |
| D | SSO 有効化を `Rails.configuration.x.sso_enabled` に集約（ENV 参照は initializer のみ） | `894bfdb` |
| T | `spec/system/sso_spec.rb` を ENV 直書きから `Rails.configuration` トグルへ | `894bfdb` |
| F | `/auth/:provider` を POST のみに（GET 経由 SSO 開始を禁止） | `f2c7371` |
| I | migration `down` で OAuth 限定ユーザー検出時にカラム追加前に `IrreversibleMigration` を raise | `f2c7371` |

### R の実装選択

選択肢として「`password = nil` リセット削除のみ」と「`after_commit` 移行」の 2 案が示されていたが、いずれも `User` インスタンスを使い回して別 attribute を `update!` する場合に仮想属性が残って PC が再 save されてしまう（プレーンテキストは同じでも bcrypt salt が変わって digest が変動）。そのため `password=` setter で `@password_pending_sync` フラグを立て、`after_save` で消費（`ensure` で必ず落とす）方式を採用。これで「`password=` で代入された直後の保存サイクルでのみ PC を同期」というセマンティクスが明確になり、再 save も発生しない。

### 追加テスト

`spec/models/user_spec.rb` に以下を追加（全 green）:

- finding B: 同じ `(provider, uid)` で再呼び出ししても `oauth_identities` が増えないこと
- finding M: `nil` / `""` / `"   "` 各 email に対して `nil` を返すこと
- finding R: `update!(password:)` で PC が更新されること、別 attribute を続けて update! しても PC が再 save されないこと
- finding J: `password_confirmation = ""` を明示渡しすると save に失敗すること

### 最終確認

- `bundle exec rspec`: 556 examples / 0 failures、Line Coverage 98.87% (1053 / 1065)
- `bin/rubocop`: 159 files inspected, no offenses detected
- 既存テスト破壊なし（`sessions_spec` / `setup_wizard_spec` / `admin/users_spec` 含めて全 green）

