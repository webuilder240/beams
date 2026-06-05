# トピック20: SSO（Google OAuth ログイン）

> 既存の自前メール+パスワード認証（[[03-auth-users]]）と**共存**する形で、Google OAuth によるシングルサインオンを追加する。
> 計画書 §7「SSO / Google OAuthログイン（オプション）」に対応。
>
> **設計方針（2026-06-05 ボス指示）**: 認証方式（identity）の情報を `User` テーブルに増やさない。
> パスワード（`password_digest`）と OAuth 情報（`provider`/`uid`）はそれぞれ専用テーブルに分離する。
> `users` テーブルは「**人**（email・role）」のみを保持し、認証手段は別の identity テーブルが担う。

- **ステータス**: 未着手（**全決定事項B1-B9 確定済み 2026-06-06**・`/agent-team` 着手可。マイグレーション承認は着手時にボスから取得）
- **依存**: [[03-auth-users]]（`User`・`SessionsController`・`Authentication` concern）/ [[05-setup-wizard]]（初回admin作成フローとの整合）
- **関連計画書**: §7（将来オプション）

---

## データモデル方針（確定 — 2026-06-05）

### テーブル分離

```
users                          ← 「人」だけを表す（emailとrole）
  id, email (unique), role, created_at, updated_at
  ※ password_digest は削除する（PasswordCredentialへ移動）

password_credentials            ← パスワード認証の identity（1対1）
  id, user_id (unique), password_digest NOT NULL, created_at, updated_at
  has_secure_password はこちらに置く

oauth_identities                ← OAuth identity（1対多、複数プロバイダに対応）
  id, user_id, provider NOT NULL, uid NOT NULL, created_at, updated_at
  unique index on (provider, uid)
```

- 既存ユーザーの `users.password_digest` はマイグレーション内で `password_credentials` に**全件コピー**し、`users` 側のカラムを削除する。
- OAuth 限定ユーザーは `password_credentials` に行を持たない（NULL 許可ではなく、行自体を持たない）。
- 1人の `User` がパスワード認証と Google OAuth の両方を併用可能。将来 Microsoft/Slack 等を追加するときは `oauth_identities` に provider を増やすだけで `users` スキーマは無変更。

### Active Record 関連

```ruby
class User < ApplicationRecord
  has_one  :password_credential, dependent: :destroy
  has_many :oauth_identities,    dependent: :destroy
end

class PasswordCredential < ApplicationRecord
  belongs_to :user
  has_secure_password           # validations: false に近い扱いはB10で決定
end

class OauthIdentity < ApplicationRecord
  belongs_to :user
  validates :provider, :uid, presence: true
  validates :uid, uniqueness: { scope: :provider }
end
```

### `User` の認証 API（既存フォームを壊さないため）

`User` は **`password=` / `password_confirmation=` の仮想属性** を提供し、`save` 時に内部で `PasswordCredential` を作成/更新する。
`User#authenticate(password)` は `password_credential&.authenticate(password)` へ委譲する。
これにより `SessionsController` や Setup ウィザード、`Admin::UsersController#reset_password` などの既存呼び出しは無変更で動作する。

---

## ボス決定事項（**全項目確定 2026-06-06**）

すべてマネージャー推奨案で確定。以下は決定内容のサマリ。

| ID | 決定内容 |
|---|---|
| **B1** ✅ | **Google OAuth のみ**。`omniauth-google-oauth2` 1プロバイダで実装。Microsoft等の拡張余地は `oauth_identities` テーブル設計に残す |
| **B2** ✅ | **`omniauth` + `omniauth-google-oauth2` + `omniauth-rails_csrf_protection`** |
| **B3** ✅ | **環境変数で保管**（`GOOGLE_OAUTH_CLIENT_ID` / `GOOGLE_OAUTH_CLIENT_SECRET`）。`ApplicationSetting` には `allowed_email_domain` だけを置く |
| **B4** ✅ | **email突合で1人1User**。既存パスワードユーザーが同じemailでOAuthログイン → `oauth_identities` 行を追加して同じ User にリンク |
| **B5** ✅ | **ドメインallowlist + 自動作成**。`ApplicationSetting#allowed_email_domain` に合致したら `role: "member"` で自動作成。空のときは未登録emailを拒否 |
| **B6** ✅ | **初回adminはメール+パスワードのみ**。OAuth設定はsetup完了後にadmin画面で（締め出し事故防止） |
| **B7** ✅ | **`ENV["GOOGLE_OAUTH_CLIENT_ID"]` が設定されている時のみ「Googleでログイン」ボタン表示** |
| **B8** ✅ | **`User#password=`・`#password_confirmation=`・`#authenticate` を `PasswordCredential` への委譲メソッドとして実装**（既存フォーム・コントローラを無変更で動かす） |
| **B9** ✅ | **`User#authenticate(password)` は `password_credential` が無ければ `false` を返す**（標準的な挙動） |

---

## ゴール（完了の定義）

- `ENV["GOOGLE_OAUTH_CLIENT_ID"]` / `ENV["GOOGLE_OAUTH_CLIENT_SECRET"]` が設定されていれば、ログイン画面に「Googleでログイン」ボタンが表示される（B7-B）
- Google OAuth でログインすると、対応する `User`/`oauth_identities` を解決して `session[:user_id]` がセットされ root にリダイレクトされる
- 既存 email のユーザーが OAuth で初ログインしたら **`oauth_identities` 行を追加して同じ User にリンク**（B4-A）
- `allowed_email_domain` が設定されていれば、合致する未登録メールは `role: "member"` で `User` を自動作成し `oauth_identities` 行を追加（B5-B）
- 既存のメール+パスワード認証は **そのまま動作**する（OAuth未設定でも全く影響を受けない）
- `users.password_digest` は **削除**され、パスワードは `password_credentials.password_digest` に格納される
- 既存ユーザーの `password_digest` データはマイグレーション内で `password_credentials` にコピーされる（ロスなし）
- `User#password=` / `User#authenticate` の仮想API は維持され、既存の `SessionsController` / Setup ウィザード / `Admin::UsersController` は無変更で動く（B8-A）
- 認証関連マイグレーションは `docs/tasks/migrations/20-users-oauth-migration.md` で承認を取ってから実行
- RSpec が通り、SimpleCov 85% 以上を維持

---

## 前提・参照（実読済み）

- `app/models/user.rb` — `has_secure_password` / `email` 一意 / `role` (admin/member)。**この `has_secure_password` を `PasswordCredential` に移す**。
- `app/controllers/sessions_controller.rb` — `user&.authenticate(params[:password])` を呼ぶ → 委譲APIで動作継続。
- `app/controllers/admin/users_controller.rb` — `reset_password` で `user.update(password: ...)` → 委譲APIで動作継続。
- `app/controllers/setup_wizard_controller.rb` — 初回admin作成で `User.create!(email:, password:, role: "admin")` → 委譲APIで動作継続。
- `db/schema.rb` の `users.password_digest NOT NULL` → **削除する**。
- `app/models/application_setting.rb` — シングルトン。`bigquery_yen_per_tb` のみ。`allowed_email_domain` を追加。

---

## タスク

### 準備：gem導入・設定

- [x] `Gemfile` に `omniauth`・`omniauth-google-oauth2`・`omniauth-rails_csrf_protection` を追加し `bundle install`（`Gemfile.lock` 更新）
  - 受け入れ条件: `bundle list | grep omniauth` に3つ出る。`bin/bundler-audit` が新規警告を出さない。
- [x] OmniAuth initializer 追加（`config/initializers/omniauth.rb`）— `ENV["GOOGLE_OAUTH_CLIENT_ID"]` が設定されている時のみ `provider :google_oauth2` を登録。`scope: "email,profile"`、`prompt: "select_account"`。
  - 受け入れ条件: ENV 未設定でも起動エラーにならない。
- [x] `bin/rubocop` クリーン。

### DBマイグレーション（事前承認ゲート）

- [x] **`docs/tasks/migrations/20-users-oauth-migration.md` を作成し、ボス承認を取る**（マイグレーション実行前に必須）。内容:
  - 新規テーブル `password_credentials`（`user_id` unique・`password_digest NOT NULL`）
  - 既存 `users.password_digest` → `password_credentials.password_digest` への**データ移行**を `up` 内で実行
  - `users.password_digest` カラムを削除
  - 新規テーブル `oauth_identities`（`user_id`・`provider`・`uid`・`(provider, uid)` unique index）
  - `application_settings.allowed_email_domain` `string null: true` を追加
  - `down` は逆順（`users.password_digest` 復元 + データ書き戻し含む）
- [x] 承認後、マイグレーション作成・実行
  - 受け入れ条件: `bin/rails db:migrate` 成功・`db:rollback` 成功（テストDB / 開発DB双方）。`db/schema.rb` に反映。**既存ユーザーのパスワードでログイン可能**であることを開発DBで実証。

### `PasswordCredential` モデル新規

- [x] `app/models/password_credential.rb` を新規作成
  - `belongs_to :user`
  - `has_secure_password`
  - `validates :user_id, uniqueness: true`
  - 受け入れ条件: モデルスペックで `create!(user:, password: "x")` 後 `authenticate("x")` が自身を返す（`spec/models/password_credential_spec.rb`）。

### `OauthIdentity` モデル新規

- [x] `app/models/oauth_identity.rb` を新規作成
  - `belongs_to :user`
  - `validates :provider, :uid, presence: true`
  - `validates :uid, uniqueness: { scope: :provider }`
  - スコープ: `scope :for, ->(provider, uid) { where(provider: provider, uid: uid) }`
  - 受け入れ条件: モデルスペック green（`spec/models/oauth_identity_spec.rb`）。

### `User` モデル改修

- [x] `app/models/user.rb` から `has_secure_password` を削除。
- [x] 関連を追加: `has_one :password_credential, dependent: :destroy`、`has_many :oauth_identities, dependent: :destroy`。
- [x] 仮想属性を追加（B8-A）:
  - `attr_accessor :password, :password_confirmation`（バリデーション用）
  - `after_save` で `password` が代入されていれば `password_credential ||= build_password_credential; password_credential.update!(password:, password_confirmation:)`
  - `validate` で `password` と `password_confirmation` の一致・最小長を `password` 代入時のみチェック
- [x] `User#authenticate(password)` を `password_credential&.authenticate(password) || false` に変更
- [x] `User.find_or_create_for_oauth(provider:, uid:, email:)` クラスメソッドを追加 — 以下を行う:
  1. `OauthIdentity.for(provider, uid).first&.user` があればそれを返す
  2. 同じ email の既存 `User` があれば `oauth_identities.create!(provider:, uid:)` を追加して返す（B4-A）
  3. `ApplicationSetting#allowed_email_domain` を満たすなら `role: "member"` で `User` を作成し `oauth_identities.create!(provider:, uid:)` で紐付け（B5-B）
  4. どれも満たさなければ `nil` を返す
- 受け入れ条件: 既存の `User.create!(email:, password:, role:)` が今までどおり成功する（仮想属性経由）。`User.find_or_create_for_oauth` の4分岐がモデルスペックで通る。`User#authenticate` が委譲で動作する。

### ApplicationSetting 拡張

- [ ] マイグレーションで `application_settings.allowed_email_domain` を追加（上記マイグレーション資料に同梱）
  - 受け入れ条件: schema 反映、既存テスト破壊なし。
- [ ] `ApplicationSetting` のバリデーション（空可・簡易ドメイン形式チェック）
  - 受け入れ条件: モデルスペック green。

### コールバック受け口・セッション

- [ ] `Auth::OmniauthCallbacksController` を作成（`app/controllers/auth/omniauth_callbacks_controller.rb`）— `google_oauth2` アクションで `request.env["omniauth.auth"]` を受け、`User.find_or_create_for_oauth(provider: "google_oauth2", uid:, email:)` の結果でログイン処理（`reset_session` → `session[:user_id]`）。`nil` 戻り時は「このメールアドレスは許可されていません」フラッシュエラー。
  - 受け入れ条件: RSpec リクエストスペックで成功・拒否双方を `OmniAuth.config.mock_auth` で検証。
- [ ] `OmniAuth.config.test_mode = true` をテスト環境で有効化（`spec/support/omniauth.rb`）。失敗用 `mock_auth` も用意。
- [ ] `config/routes.rb` に OAuth ルートを追加 — `get "/auth/google_oauth2/callback"`、`get "/auth/failure"`、`post "/auth/:provider"`（CSRF passthru）
  - 受け入れ条件: `rails routes | grep auth` に出る。

### ログイン画面

- [ ] `app/views/sessions/new.html.erb` に「Googleでログイン」ボタンを追加。`ENV["GOOGLE_OAUTH_CLIENT_ID"].present?` のときのみ表示（B7-B）。`button_to "/auth/google_oauth2", method: :post, data: { turbo: false }`。
  - 受け入れ条件: System Spec で ENV 設定時に見え、未設定時に見えない。

### admin 設定画面（allowed_email_domain）

- [ ] `Admin::SettingsController#edit` / `update` に `allowed_email_domain` 編集UI追加（`app/views/admin/settings/edit.html.erb`）
  - 受け入れ条件: admin が保存可・member は弾かれる（System Spec）。

### テスト

- [ ] `spec/models/password_credential_spec.rb` — 作成・認証・バリデーション
- [ ] `spec/models/oauth_identity_spec.rb` — 作成・`(provider,uid)` 一意性
- [ ] `spec/models/user_spec.rb` を改修 — 仮想属性経由のパスワード設定、`authenticate` 委譲、`find_or_create_for_oauth` の4分岐
- [ ] `spec/requests/auth/omniauth_callbacks_spec.rb` — 成功（既存email リンク・自動作成）/ 拒否（domain不一致）/ failure
- [ ] `spec/system/sso_spec.rb`（`rack_test`）— ログインボタン表示・OmniAuth mock 経由でログイン成功 → ダッシュボード
- [ ] 既存テスト（`spec/requests/sessions_spec.rb`、`spec/system/sessions_spec.rb`、`spec/requests/admin/users_spec.rb`、setup wizard 関連）が壊れていない
- [ ] **Factory修正**: `spec/factories/users.rb` を仮想属性経由のままにする（外部APIは無変更にする）

### ドキュメント

- [ ] `docs/PRODUCT_PLAN.md` §7 の該当行に「実装済み（トピック20）」を注記
- [ ] `docs/tasks/progress/20-sso.md` を作成し時系列ログを残す（Coder/Tester共通）
- [ ] **新規 ADR**: `docs/adr/0002-identity-table-separation.md` を作成して「`users` から認証方式を分離した設計理由」を残す（将来の改修時に意図が消えないように）

---

## 動作確認

- [ ] マイグレーション後、既存パスワード認証ユーザーで通常ログイン可能（データ移行が正しい）
- [ ] `GOOGLE_OAUTH_CLIENT_ID` / `GOOGLE_OAUTH_CLIENT_SECRET` を設定して起動 → `/session/new` に「Googleでログイン」ボタン表示
- [ ] ENV 未設定で起動 → ボタンが表示されず従来通り動作
- [ ] OmniAuth mock 経由のE2Eで実Google通信なしにログイン → ダッシュボード
- [ ] `allowed_email_domain` 未設定で未登録emailは拒否
- [ ] `allowed_email_domain = "example.com"` で `x@example.com` は member 自動作成、`x@other.com` は拒否
- [ ] 既存 `user@example.com`（パスワード認証）が同じ Google でログイン → `oauth_identities` 行が追加され同じ User にリンクされる
- [ ] OAuth のみで作られたユーザーが古い `password` で認証しても弾かれる（B9-A）
- [ ] `bin/rubocop` / `bin/brakeman` / `bin/bundler-audit` クリーン
- [ ] `bundle exec rspec` 全 green、SimpleCov 85% 以上

---

## 未決事項・質問

なし（B1〜B9 はすべて確定済み 2026-06-06）。
`/agent-team` 着手可。マイグレーション計画（`docs/tasks/migrations/20-users-oauth-migration.md`）の最終承認は Coder が実行する直前にボスから取得する。
