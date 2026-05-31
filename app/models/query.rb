class Query < ApplicationRecord
  belongs_to :user
  belongs_to :bigquery_connection, class_name: "Bigquery::Connection"

  validates :title, presence: true
  validates :sql_body, presence: true

  # タイトル部分一致検索（§4.11）。空クエリは全件を返す。
  scope :title_matching, ->(term) {
    next all if term.blank?

    where("title LIKE ?", "%#{sanitize_sql_like(term)}%")
  }
end
