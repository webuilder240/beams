# アプリ全体のシングルトン設定（行は常に 1 つ）。
# 将来は他の設定値も保持し得る汎用設定の置き場。現状は BigQuery の
# GB→円換算レート（`bigquery_yen_per_tb`）のみを持つ。
#
# シングルトンの担保はモデル側で行う（DB では 1 行強制しない）。
# 全アクセスは `ApplicationSetting.instance` 経由とする。
class ApplicationSetting < ApplicationRecord
  validates :bigquery_yen_per_tb,
            presence: true,
            numericality: { greater_than_or_equal_to: 0 }

  # 唯一の設定行を返す。無ければデフォルト（DB の default 950.0）で生成する。
  def self.instance
    first_or_create!
  end
end
