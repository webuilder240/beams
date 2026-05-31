require "json"
require "google/cloud/bigquery"

class Bigquery::Connection < ApplicationRecord
  # SA JSON 鍵は Active Record Encryption で暗号化して保存する（平文は DB に書かない）。
  encrypts :service_account_json

  validates :name, presence: true
  validates :project_id,
            presence: true,
            format: { with: /\A[a-zA-Z0-9-]+\z/, message: "は英数字とハイフンのみ使用できます" }
  validates :service_account_json, presence: true
  validate :service_account_json_must_be_a_json_object
  validates :maximum_bytes_billed,
            numericality: { only_integer: true, greater_than: 0 },
            allow_nil: true

  # SA JSON 鍵とプロジェクト ID から BigQuery クライアントを生成して返す。
  # credentials にはパース済みのハッシュをそのまま渡せるため、一時ファイルは不要。
  def bigquery
    @bigquery ||= Google::Cloud::Bigquery.new(
      project_id: project_id,
      credentials: parsed_service_account
    )
  end

  private

  def parsed_service_account
    JSON.parse(service_account_json)
  end

  def service_account_json_must_be_a_json_object
    return if service_account_json.blank?

    parsed = JSON.parse(service_account_json)
    errors.add(:service_account_json, "はJSONオブジェクトである必要があります") unless parsed.is_a?(Hash)
  rescue JSON::ParserError
    errors.add(:service_account_json, "は正しいJSON形式である必要があります")
  end
end
