# パスワード認証の identity（[[20-sso]]）。
# 1 ユーザー 1 行の関係（`user_id` ユニーク）。OAuth 限定ユーザーはこのテーブルに
# 行を持たない。`has_secure_password` をここに置くことで `users` テーブルから
# 認証カラムを排除している（identity 分離）。
class PasswordCredential < ApplicationRecord
  belongs_to :user

  has_secure_password

  validates :user_id, uniqueness: true
end
