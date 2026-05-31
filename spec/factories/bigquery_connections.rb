FactoryBot.define do
  factory :bigquery_connection, class: "Bigquery::Connection" do
    sequence(:name) { |n| "接続#{n}" }
    project_id { "my-project-#{rand(1000)}" }
    service_account_json do
      {
        type: "service_account",
        project_id: "my-project",
        private_key_id: Faker::Alphanumeric.alphanumeric(number: 32),
        private_key: "-----BEGIN PRIVATE KEY-----\n#{Faker::Crypto.sha256}\n-----END PRIVATE KEY-----\n",
        client_email: Faker::Internet.email,
        client_id: Faker::Number.number(digits: 21).to_s
      }.to_json
    end
    maximum_bytes_billed { nil }

    trait :with_cost_limit do
      maximum_bytes_billed { 10_000_000_000 }
    end
  end
end
