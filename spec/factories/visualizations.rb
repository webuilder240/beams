FactoryBot.define do
  factory :visualization do
    association :query
    chart_type { "line" }
    display_mode { "table" }
    counter_aggregation { "sum" }
  end
end
