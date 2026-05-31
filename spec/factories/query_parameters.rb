FactoryBot.define do
  factory :query_parameter do
    association :query
    sequence(:name) { |n| "param_#{n}" }
    param_type { "string" }
  end
end
