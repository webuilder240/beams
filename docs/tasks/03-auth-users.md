# トピック03: 認証・ユーザー

> Rails 8標準の `has_secure_password` を用いた自前メール+パスワード認証と、admin/member 2ロールによる認可を実装する。計画書 §4.1 に対応。

- **ステータス**: 未着手
- **依存**: [[01-foundation-rename]]（アプリモジュール名 `Beams` への変更、`bcrypt` 有効化、Active Record Encryption 設定が完了していること）
- **関連計画書**: §4.1

## ゴール（完了の定義）

- `User` モデルが `has_secure_password` を使いメール+パスワード認証できる
- ロールは `admin` / `member` の 2 種類で、カラムで管理されている
- ログイン・ログアウト・セッション管理が動作する
- admin のみが接続管理・ユーザー管理画面にアクセスできる認可が動作する
- member はクエリ作成・実行・共有のみ行える
- SSO/OAuth は実装しない
- RSpec で主要パスがカバーされ、SimpleCov 85% 以上を維持する

## 前提・参照

- [[01-foundation-rename]] 完了後に着手（`bcrypt` gem が有効化済み、`Beams` モジュール名確定済み）
- Active Record Encryption の設定キー生成は [[01-foundation-rename]] 側で実施済みであること
- Rails 8 の `has_secure_password` ドキュメント: https://api.rubyonrails.org/classes/ActiveModel/SecurePassword/ClassMethods.html
- Rails 8 の認証ジェネレータ（`rails generate authentication`）の出力を参考に、ただし Beams の命名・構造に合わせて調整する

## タスク

### User モデル

- [ ] `User` モデル・マイグレーション作成（`app/models/user.rb`, `db/migrate/YYYYMMDDHHMMSS_create_users.rb`）— `email:string`, `password_digest:string`, `role:string`（`"admin"` / `"member"`）, `created_at`, `updated_at`
  - 受け入れ条件: `rails db:migrate` が通り、`User.new` でインスタンスが作れる。`email` に一意インデックスが存在する
- [ ] `User` モデルに `has_secure_password` + バリデーション追加（`app/models/user.rb`）— email 必須・一意・フォーマット、role の enum/inclusion 検証
  - 受け入れ条件: `User.create!(email: "a@example.com", password: "pass", role: "admin")` が保存できる。不正な email やパスワードなしは保存されない
- [ ] FactoryBot ファクトリ作成（`spec/factories/users.rb`）— `admin` / `member` のトレイト付き
  - 受け入れ条件: `create(:user, :admin)` と `create(:user, :member)` が RSpec 内で使える
- [ ] `User` モデル単体テスト（`spec/models/user_spec.rb`）— バリデーション・`authenticate` メソッドの正常/異常系
  - 受け入れ条件: `bundle exec rspec spec/models/user_spec.rb` がグリーン

### セッション（ログイン・ログアウト）

- [ ] `SessionsController` 作成（`app/controllers/sessions_controller.rb`）— `new`（ログインフォーム）, `create`（認証）, `destroy`（ログアウト）
  - 受け入れ条件: 正しいメール+パスワードで `session[:user_id]` がセットされ、誤認証はフラッシュエラーを出してフォームに戻る
- [ ] ルーティング追加（`config/routes.rb`）— `resource :session, only: [:new, :create, :destroy]`
  - 受け入れ条件: `rails routes` で `new_session`, `session`, `destroy_session` のパスが確認できる
- [ ] ログインフォームビュー作成（`app/views/sessions/new.html.erb`）— email・password フィールド、送信ボタン
  - 受け入れ条件: `GET /session/new` でフォームが表示される
- [ ] `ApplicationController` にヘルパーメソッド追加（`app/controllers/application_controller.rb`）— `current_user`, `logged_in?`, `require_login`（before_action 用）
  - 受け入れ条件: `current_user` が `session[:user_id]` に対応する User を返す。未ログインで保護ページにアクセスするとログイン画面にリダイレクトされる
- [ ] `SessionsController` の RSpec テスト（`spec/requests/sessions_spec.rb`）— 正常ログイン・誤認証・ログアウトのリクエストスペック
  - 受け入れ条件: `bundle exec rspec spec/requests/sessions_spec.rb` がグリーン

### ロールによる認可

- [ ] `require_admin` before_action を `ApplicationController` に追加（`app/controllers/application_controller.rb`）— admin 以外のアクセスを 403 または root にリダイレクト
  - 受け入れ条件: member ユーザーで admin 専用パスにアクセスすると弾かれる
- [ ] 認可ヘルパーのモジュール化（`app/controllers/concerns/authentication.rb`）— `require_login`, `require_admin` を Concern として切り出し
  - 受け入れ条件: `ApplicationController` が `include Authentication` で利用でき、コントローラが薄くなっている
- [ ] 認可の RSpec テスト（`spec/requests/authorization_spec.rb`）— member が admin 専用エンドポイントにアクセスしたときのレスポンス検証
  - 受け入れ条件: `bundle exec rspec spec/requests/authorization_spec.rb` がグリーン

### ユーザー管理（admin 専用 CRUD）

- [ ] `UsersController`（admin 専用）作成（`app/controllers/users_controller.rb`）— `index`, `new`, `create`, `edit`, `update`, `destroy`。`before_action :require_admin`
  - 受け入れ条件: admin でログインした状態でユーザー一覧・作成・編集・削除が動作する。member でアクセスすると弾かれる
- [ ] ユーザー管理ビュー作成（`app/views/users/`）— 一覧・新規作成フォーム・編集フォーム（Hotwire/Turbo で標準的なフォーム送信）
  - 受け入れ条件: 画面からユーザーの CRUD が一通りできる
- [ ] ルーティング追加（`config/routes.rb`）— `resources :users` を admin 名前空間またはフラット配置（計画書に制約なし、判断は実装者に委ねる）
  - 受け入れ条件: `rails routes` で users の CRUD パスが確認できる
- [ ] `UsersController` の RSpec テスト（`spec/requests/users_spec.rb`）— admin による CRUD、member によるアクセス拒否
  - 受け入れ条件: `bundle exec rspec spec/requests/users_spec.rb` がグリーン
- [ ] admin による任意ユーザーのパスワードリセット（再発行）機能（`app/controllers/admin/users_controller.rb` の `reset_password` アクション、または編集フォームでのパスワード変更）
  - 受け入れ条件: admin がユーザー詳細/編集画面から新パスワードを設定でき、対象ユーザーがそのパスワードでログインできる（`spec/requests/users_spec.rb` 内のリクエストスペックで検証）

### System Spec

- [ ] ログイン/ログアウトのシステムスペック（`spec/system/sessions_spec.rb`）— rack_test ドライバー、正常ログイン→ダッシュボード遷移・ログアウト
  - 受け入れ条件: `bundle exec rspec spec/system/sessions_spec.rb` がグリーン
- [ ] ユーザー管理のシステムスペック（`spec/system/users_spec.rb`）— admin でユーザー作成・ロール変更・削除を画面操作で検証
  - 受け入れ条件: `bundle exec rspec spec/system/users_spec.rb` がグリーン

## 動作確認

- [ ] `bundle exec rails db:migrate` → エラーなし
- [ ] `rails console` で `User.create!(email: "admin@example.com", password: "password", role: "admin")` が保存され、`user.authenticate("password")` が user を返す
- [ ] ブラウザで `/session/new` にアクセス → ログインフォームが表示される
- [ ] 正しい認証情報でログイン → セッションが確立され保護ページに遷移する
- [ ] 誤ったパスワードでログイン → エラーメッセージが表示されフォームに留まる
- [ ] member アカウントで admin 専用 URL にアクセス → 弾かれる
- [ ] `bundle exec rspec spec/models/user_spec.rb spec/requests/sessions_spec.rb spec/requests/authorization_spec.rb spec/requests/users_spec.rb spec/system/sessions_spec.rb spec/system/users_spec.rb` → 全グリーン
- [ ] `bundle exec rspec` → SimpleCov 85% 以上

## 未決事項・質問

- ✅決定: メール送信は作らず、adminによるパスワード再発行で代替（2026-05-31）
- ユーザー管理のルーティングを名前空間（`/admin/users`）にするかフラット（`/users`）にするか。計画書に制約なし。
