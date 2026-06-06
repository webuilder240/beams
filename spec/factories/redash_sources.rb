FactoryBot.define do
  factory :redash_source do
    sequence(:name) { |n| "Redash 接続#{n}" }
    url { "https://redash.example.com" }
    api_key { "test_api_key_#{SecureRandom.hex(8)}" }
  end
end
