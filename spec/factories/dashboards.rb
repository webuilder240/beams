FactoryBot.define do
  factory :dashboard do
    association :user
    sequence(:title) { |n| "ダッシュボード#{n}" }
    description { nil }
  end
end
