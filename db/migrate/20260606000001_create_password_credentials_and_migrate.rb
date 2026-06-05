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
    # rollback 前に OAuth 限定ユーザー（password_credentials を持たない User）を
    # 削除する／一時パスワードを設定する必要があるが、現状はその運用が発生したら
    # ドキュメント化する（YAGNI）。
    change_column_null :users, :password_digest, false

    drop_table :password_credentials
  end
end
