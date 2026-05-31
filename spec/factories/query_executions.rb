FactoryBot.define do
  factory :query_execution do
    association :query
    status { "pending" }

    trait :running do
      status { "running" }
      started_at { Time.current }
    end

    trait :succeeded do
      status { "succeeded" }
      started_at { 1.minute.ago }
      finished_at { Time.current }
      result_row_count { 1 }
      result_truncated { false }
    end

    trait :failed do
      status { "failed" }
      started_at { 1.minute.ago }
      finished_at { Time.current }
      error_message { "boom" }
    end
  end
end
