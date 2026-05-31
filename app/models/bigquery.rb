module Bigquery
  # Active Record のネームスペース用テーブルプレフィックス。
  # これにより Bigquery::Connection は bigquery_connections テーブルにマップされる。
  def self.table_name_prefix
    "bigquery_"
  end
end
