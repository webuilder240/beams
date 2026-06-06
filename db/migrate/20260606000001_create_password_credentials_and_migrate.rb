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
    # 既存仕様（NOT NULL の password_digest）に戻せるかをカラム追加前に検証する。
    # OAuth 限定ユーザー（password_credentials を持たない User）がいる場合は
    # ロールバック時にデータ損失となるため明示的に失敗させる（finding I）。
    # この時点ではスキーマ変更が始まっていないので失敗しても schema は無傷で済む。
    oauth_only = select_value(<<~SQL).to_i
      SELECT COUNT(*) FROM users u
      LEFT JOIN password_credentials pc ON pc.user_id = u.id
      WHERE pc.id IS NULL
    SQL
    if oauth_only.positive?
      raise ActiveRecord::IrreversibleMigration,
            "OAuth-only users exist (#{oauth_only}). Remove them or assign temporary passwords before rollback."
    end

    add_column :users, :password_digest, :string

    execute <<~SQL
      UPDATE users SET password_digest = (
        SELECT password_digest FROM password_credentials
        WHERE password_credentials.user_id = users.id
      )
    SQL

    # 既存仕様（NOT NULL）に戻す。事前ガードで OAuth-only ユーザーは弾いている
    # ので、ここまで来れば全 users 行に digest が入っているはず。
    change_column_null :users, :password_digest, false

    drop_table :password_credentials
  end
end
