class User < ApplicationRecord
  ROLES = %w[admin member].freeze

  # 認証 identity（[[20-sso]]）。`users` には認証カラムを持たせず、
  # パスワードは `password_credentials`、OAuth は `oauth_identities` に分離する。
  has_one :password_credential, dependent: :destroy
  has_many :oauth_identities, dependent: :destroy

  has_many :queries, dependent: :destroy

  normalizes :email, with: ->(email) { email.strip.downcase }

  validates :email,
            presence: true,
            uniqueness: { case_sensitive: false },
            format: { with: URI::MailTo::EMAIL_REGEXP }
  validates :role, presence: true, inclusion: { in: ROLES }

  # `password=` / `password_confirmation=` の仮想属性経由で
  # `PasswordCredential` を作成/更新する（既存の `User.create!(email:, password:)` を
  # 維持するため）。ボス決定事項 B8-A。
  #
  # `password_credential` 同期は「直前に password= で代入された場合のみ」走らせる
  # ため、setter で `@password_pending_sync` を立てて、`after_save` で消費する。
  # これにより `password=` のあと別属性を update! しても PC を再 save しない。
  attr_accessor :password_confirmation
  attr_reader :password

  def password=(value)
    @password = value
    @password_pending_sync = true
  end

  # 新規ユーザーは（OAuth 経由を除いて）password 必須（既存仕様の維持）。
  validate :password_present_for_new_password_user
  validate :password_confirmation_matches, if: -> { password.present? && !password_confirmation.nil? }

  after_save :sync_password_credential, if: :password_needs_sync?

  def admin?
    role == "admin"
  end

  def member?
    role == "member"
  end

  # 既存呼び出し（`SessionsController` 等）から呼ばれる。
  # `password_credential` が無ければ常に `false`（B9-A）。
  def authenticate(submitted_password)
    return false unless password_credential&.authenticate(submitted_password)

    self
  end

  # OmniAuth コールバックから呼ばれる解決ロジック（B4-A / B5-B）。
  #
  # 1. `oauth_identities` から `(provider, uid)` で既存ユーザーを見つけたら返す
  # 2. 同じ email の既存 `User` があれば identity を追加してリンクして返す
  # 3. `ApplicationSetting#allowed_email_domain` を満たす未登録 email は
  #    `role: "member"` で `User` を新規作成し identity を追加
  # 4. どれにも該当しなければ `nil`（拒否）
  def self.find_or_create_for_oauth(provider:, uid:, email:)
    normalized_email = email.to_s.strip.downcase
    return nil if normalized_email.blank?

    transaction do
      if (identity = OauthIdentity.for(provider, uid).first)
        next identity.user
      end

      if (existing = find_by(email: normalized_email))
        existing.oauth_identities.find_or_create_by!(provider: provider, uid: uid)
        next existing
      end

      next nil unless allowed_oauth_email?(normalized_email)

      user = new(email: normalized_email, role: "member")
      user.skip_password_validation = true
      user.save!
      user.oauth_identities.find_or_create_by!(provider: provider, uid: uid)
      user
    end
  end

  def self.allowed_oauth_email?(email)
    domain = ApplicationSetting.instance.allowed_email_domain.to_s.strip.downcase
    return false if domain.blank?

    email.to_s.end_with?("@#{domain}")
  end

  # OAuth 経由の新規作成時にパスワード必須バリデーションをスキップする内部フラグ。
  attr_accessor :skip_password_validation

  private

  def password_present_for_new_password_user
    return unless new_record?
    return if skip_password_validation
    return if password.present?
    errors.add(:password, :blank)
  end

  def password_confirmation_matches
    return if password.to_s == password_confirmation.to_s
    errors.add(:password_confirmation, :confirmation, attribute: User.human_attribute_name(:password))
  end

  def password_needs_sync?
    @password_pending_sync && password.to_s.present?
  end

  def sync_password_credential
    pc = password_credential || build_password_credential
    pc.password = password
    pc.password_confirmation = password_confirmation unless password_confirmation.nil?
    pc.save!
  ensure
    # 1 度の save サイクルで同期されたら次の update では再 save しない。
    # 仮想属性自体は他の場所で参照される可能性があるので残す。
    @password_pending_sync = false
  end
end
