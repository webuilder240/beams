Rails.application.routes.draw do
  # Define your application routes per the DSL in https://guides.rubyonrails.org/routing.html

  # Reveal health status on /up that returns 200 if the app boots with no exceptions, otherwise 500.
  # Can be used by load balancers and uptime monitors to verify that the app is live.
  get "up" => "rails/health#show", as: :rails_health_check

  # Render dynamic PWA files from app/views/pwa/* (remember to link manifest in application.html.erb)
  # get "manifest" => "rails/pwa#manifest", as: :pwa_manifest
  # get "service-worker" => "rails/pwa#service_worker", as: :pwa_service_worker

  # 認証（自前メール+パスワード）
  resource :session, only: [ :new, :create, :destroy ]

  # ユーザー管理（admin 専用）
  namespace :admin do
    resources :users, except: [ :show ] do
      member do
        patch :reset_password
      end
    end
  end

  # BigQuery 接続管理（admin 専用）
  namespace :bigquery do
    resources :connections, except: [ :show ]
  end

  # 初回セットアップウィザード（ユーザー 0 件のときに誘導）
  get "setup" => "setup_wizard#index", as: :setup
  get "setup/step1" => "setup_wizard#step1", as: :setup_step1
  post "setup/step1" => "setup_wizard#create_step1"
  get "setup/step2" => "setup_wizard#step2", as: :setup_step2
  post "setup/step2" => "setup_wizard#create_step2"
  get "setup/step3" => "setup_wizard#step3", as: :setup_step3
  get "setup/step4" => "setup_wizard#step4", as: :setup_step4
  post "setup/step4" => "setup_wizard#create_step4"

  # Defines the root path route ("/")
  root "dashboard#show"
end
