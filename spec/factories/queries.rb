FactoryBot.define do
  factory :query do
    association :user
    association :bigquery_connection, factory: :bigquery_connection
    sequence(:title) { |n| "クエリ#{n}" }
    sql_body { "SELECT 1" }
  end
end
