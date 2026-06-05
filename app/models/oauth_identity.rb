# OAuth プロバイダによる identity（[[20-sso]]）。
# 1 ユーザーが複数プロバイダ（将来の Microsoft / Slack 等）にリンク可能。
# プロバイダ側 uid の重複は `(provider, uid)` ユニーク制約で禁止する。
class OauthIdentity < ApplicationRecord
  belongs_to :user

  validates :provider, :uid, presence: true
  validates :uid, uniqueness: { scope: :provider }

  scope :for, ->(provider, uid) { where(provider: provider, uid: uid) }
end
