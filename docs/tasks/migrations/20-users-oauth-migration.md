# マイグレーション確認用ドキュメント: identity テーブル分離（`password_credentials` / `oauth_identities` 新設、`users.password_digest` 削除、`application_settings.allowed_email_domain` 追加）

> トピック **20-sso**（SSO/Google OAuth）の DB 変更。
> **設計方針（2026-06-05 ボス指示）**: `users` テーブルに認証方式（password/oauth）カラムを増やさない。
> パスワードと OAuth 情報はそれぞれ専用テーブル（identity 群）に分離する。
>
> **このドキュメントの承認後に `bin/rails db:migrate` を実行する。承認前は実行しない。**
> **既存データを移行する破壊的変更を含む** ため、開発DB / 本番DB（あれば）でのバックアップが事前に必要。

- **対象マイグレーション**（予定）:
  1. `db/migrate/YYYYMMDDHHMMSS_create_password_credentials_and_migrate.rb`（テーブル作成 + データ移行 + `users.password_digest` 削除）
  2. `db/migrate/YYYYMMDDHHMMSS_create_oauth_identities.rb`
  3. `db/migrate/YYYYMMDDHHMMSS_add_allowed_email_domain_to_application_settings.rb`
- **作成日**: 2026-06-05（マネージャー起票）
- **担当**: Coder（着手前）
- **ステータス**: 承認待ち・未実行（**承認は `/agent-team` 着手時に Coder が実行する直前にボスから取得する**）

---

## 1. 追加・変更するテーブル

### テーブル: `password_credentials`（新規）

> パスワード認証の identity を保持する。OAuth 限定ユーザーはこのテーブルに行を持たない。

| カラム名 | 型 | NULL | デフォルト | 制約・備考 |
|---|---|:---:|---|---|
| `id` | integer (PK) | NOT NULL | 自動採番 | Rails 標準主キー |
| `user_id` | integer (FK) | NOT NULL | なし | `users.id` への外部キー。**`unique`**（1ユーザー1パスワード） |
| `password_digest` | string | NOT NULL | なし | `has_secure_password`（bcrypt）が使うハッシュ格納カラム |
| `created_at` | datetime | NOT NULL | なし | `t.timestamps` |
| `updated_at` | datetime | NOT NULL | なし | `t.timestamps` |

**インデックス**:
| 名前 | 対象 | 種別 | 目的 |
|---|---|---|---|
| `index_password_credentials_on_user_id` | `user_id` | UNIQUE | 1ユーザー1パスワード、リレーション解決の高速化 |

### テーブル: `oauth_identities`（新規）

> OAuth プロバイダによる identity を保持する。1ユーザーが複数プロバイダにリンク可能（将来Microsoft/Slack追加時もスキーマ無変更）。

| カラム名 | 型 | NULL | デフォルト | 制約・備考 |
|---|---|:---:|---|---|
| `id` | integer (PK) | NOT NULL | 自動採番 | Rails 標準主キー |
| `user_id` | integer (FK) | NOT NULL | なし | `users.id` への外部キー |
| `provider` | string | NOT NULL | なし | 例: `"google_oauth2"` |
| `uid` | string | NOT NULL | なし | プロバイダ側のユーザーID |
| `created_at` | datetime | NOT NULL | なし | `t.timestamps` |
| `updated_at` | datetime | NOT NULL | なし | `t.timestamps` |

**インデックス**:
| 名前 | 対象 | 種別 | 目的 |
|---|---|---|---|
| `index_oauth_identities_on_provider_and_uid` | `(provider, uid)` | UNIQUE | 同一プロバイダの uid 重複を防ぐ |
| `index_oauth_identities_on_user_id` | `user_id` | （非unique） | リレーション解決の高速化 |

### テーブル: `users`（変更）

| カラム名 | 変更内容 |
|---|---|
| `password_digest` | **削除**（`password_credentials.password_digest` に移行する） |

> その他のカラム（`email`, `role`, タイムスタンプ）は **無変更**。

### テーブル: `application_settings`（変更）

| カラム名 | 型 | NULL | デフォルト | 備考 |
|---|---|:---:|---|---|
| `allowed_email_domain` | string | YES | なし | OAuth 自動プロビジョニングを許可するメールドメイン（例: `"example.com"`）。空のとき自動作成を行わない |

---

## 2. マイグレーション本文（予定）

### 2.1 `password_credentials` 作成 + データ移行 + `users.password_digest` 削除

> **重要**: 1つのマイグレーション内で「テーブル作成 → データ移行 → カラム削除」をトランザクションで実行する。
> 途中失敗時は SQLite のトランザクションで全体ロールバックされる（DDL も含む。SQLite はDDLがトランザクション内で動く）。

```ruby
# db/migrate/YYYYMMDDHHMMSS_create_password_credentials_and_migrate.rb
class CreatePasswordCredentialsAndMigrate < ActiveRecord::Migration[8.1]
  def up
    create_table :password_credentials do |t|
      t.references :user, null: false, foreign_key: true, index: { unique: true }
      t.string :password_digest, null: false
      t.timestamps
    end

    # 既存ユーザーのパスワードを password_credentials にコピー
    # （SQLite で動く SQL のみ使用。Rails モデルに依存しない＝マイグレーションの安定性確保）
    execute <<~SQL
      INSERT INTO password_credentials (user_id, password_digest, created_at, updated_at)
      SELECT id, password_digest, created_at, updated_at
      FROM users
      WHERE password_digest IS NOT NULL AND password_digest != ''
    SQL

    # 移行件数の確認（情報のみ）
    moved = select_value("SELECT COUNT(*) FROM password_credentials").to_i
    total = select_value("SELECT COUNT(*) FROM users").to_i
    say "Migrated #{moved} / #{total} user password_digests to password_credentials"

    remove_column :users, :password_digest
  end

  def down
    add_column :users, :password_digest, :string

    execute <<~SQL
      UPDATE users SET password_digest = (
        SELECT password_digest FROM password_credentials
        WHERE password_credentials.user_id = users.id
      )
    SQL

    # 既存仕様（NOT NULL）に戻すが、null 行があれば失敗する。
    # rollback 前に OAuth限定ユーザーを削除する必要がある旨は運用ドキュメントに記載。
    change_column_null :users, :password_digest, false

    drop_table :password_credentials
  end
end
```

### 2.2 `oauth_identities` 作成

```ruby
# db/migrate/YYYYMMDDHHMMSS_create_oauth_identities.rb
class CreateOauthIdentities < ActiveRecord::Migration[8.1]
  def change
    create_table :oauth_identities do |t|
      t.references :user, null: false, foreign_key: true
      t.string :provider, null: false
      t.string :uid, null: false
      t.timestamps
    end

    add_index :oauth_identities, [:provider, :uid], unique: true
  end
end
```

### 2.3 `application_settings.allowed_email_domain` 追加

```ruby
# db/migrate/YYYYMMDDHHMMSS_add_allowed_email_domain_to_application_settings.rb
class AddAllowedEmailDomainToApplicationSettings < ActiveRecord::Migration[8.1]
  def change
    add_column :application_settings, :allowed_email_domain, :string
  end
end
```

---

## 3. 既存データへの影響

### 3.1 ユーザーのパスワードデータ

- **すべての既存ユーザーで `password_digest` は移行される**。`up` 内の `INSERT ... SELECT` が `users` を全件走査し `password_credentials` にコピー。
- マイグレーション後、`User#authenticate(...)` は `password_credential&.authenticate(...)` に委譲されるため、**既存ユーザーは同じパスワードでログイン可能**。
- 既存ユーザーで `password_digest` が NULL/空の行は移行対象外（そもそも認証できない不整合データ）。本番に存在しないはずだが、`spec/models/user_spec.rb` で「`password_credential` を持たない User は `authenticate` で常に `false`」をテストする。

### 3.2 `users.password_digest` 削除

- カラム自体が消えるので、削除前にこのカラムを参照するコード（`User#has_secure_password` 由来のもの）は全て移行・除去する必要がある。本トピックの `User` モデル改修と同一PR内で行う。

### 3.3 `oauth_identities` / `allowed_email_domain`

- 初期データなし。OAuth ログイン時に追加される。
- `application_settings` の既存 1 行に `allowed_email_domain = NULL` で追加。OAuth未設定の運用では何も変わらない。

---

## 4. ロールバック計画

- **`down` は理論上動くが、OAuth 限定ユーザーが存在すると `password_digest NOT NULL` 制約に違反して失敗する**。
- ロールバック前に運用側で次のいずれかが必要:
  1. OAuth 限定ユーザー（`password_credentials` 行を持たない User）を事前に削除する
  2. または、それらの User に一時パスワードを設定してから rollback する
- これらの手順は将来必要になった時に運用ドキュメントへ追記する（今は YAGNI、`down` のコメントで言及）。

---

## 5. テスト計画

### 5.1 マイグレーション単体

- `bin/rails db:migrate` 成功（development・test）
- `bin/rails db:rollback STEP=3` 成功（OAuth限定ユーザーなしの状態で）
- `db/schema.rb` への反映確認

### 5.2 データ移行の正しさ

- マイグレーション前に存在したユーザーがマイグレーション後も同じパスワードでログインできる（`spec/system/sessions_spec.rb` または開発DBで手動確認）
- `password_credentials.count == users.count`（OAuth限定ユーザーがいない時点で）

### 5.3 モデル単体

- `User` モデル: `password=` 仮想属性経由で `PasswordCredential` が作られる
- `User#authenticate` が委譲動作する
- `PasswordCredential`: `(user_id)` ユニーク制約・`has_secure_password` の挙動
- `OauthIdentity`: `(provider, uid)` ユニーク制約

---

## 6. 承認

`/agent-team` 着手時に Coder が以下を順番に実施し、各ステップでボス承認を得ながら進める。

- [ ] ボス承認（着手時）— 本ドキュメントを最新のコードベース状態で再確認のうえ承認を取る
- [ ] 開発DB バックアップ（`storage/development.sqlite3` のコピー）
- [ ] `bin/rails db:migrate` 実行
- [ ] `db/schema.rb` 反映確認
- [ ] テストDB 再構築（`bin/rails db:test:prepare`）
- [ ] 既存ユーザーで動作確認（同じパスワードでログイン可）

承認なしでは Coder/Agent はこのマイグレーションを実行しない。
