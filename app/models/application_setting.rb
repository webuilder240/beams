# アプリ全体のシングルトン設定（行は常に 1 つ）。
# 将来は他の設定値も保持し得る汎用設定の置き場。現状は BigQuery の
# GB→円換算レート（`bigquery_yen_per_tb`）のみを持つ。
#
# シングルトンの担保はモデル側で行う（DB では 1 行強制しない）。
# 全アクセスは `ApplicationSetting.instance` 経由とする。
class ApplicationSetting < ApplicationRecord
  # OAuth 自動プロビジョニングを許可するドメインの簡易フォーマット（labels.tld 形式）。
  # ホスト名としては不完全だが、ユーザーが誤って `@example.com` 等を入れたときに
  # 弾けるくらいの最低限のチェックを掛ける（[[20-sso]] B5-B）。
  DOMAIN_FORMAT = /\A(?:[a-z0-9](?:[a-z0-9-]*[a-z0-9])?\.)+[a-z]{2,}\z/i

  validates :bigquery_yen_per_tb,
            presence: true,
            numericality: { greater_than_or_equal_to: 0 }

  validates :allowed_email_domain,
            format: { with: DOMAIN_FORMAT },
            allow_blank: true

  # 唯一の設定行を返す。無ければデフォルト（DB の default 950.0）で生成する。
  def self.instance
    first_or_create!
  end
end
