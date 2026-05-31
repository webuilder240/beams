FactoryBot.define do
  factory :user do
    sequence(:email) { |n| "user#{n}@example.com" }
    password { "password" }
    role { "member" }

    trait :admin do
      role { "admin" }
    end

    trait :member do
      role { "member" }
    end
  end
end
