FactoryBot.define do
  factory :widget do
    association :dashboard
    association :query
    position { 0 }
    column_span { 1 }
    title_override { nil }
  end
end
