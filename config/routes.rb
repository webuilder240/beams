Rails.application.routes.draw do
  # Define your application routes per the DSL in https://guides.rubyonrails.org/routing.html

  # Reveal health status on /up that returns 200 if the app boots with no exceptions, otherwise 500.
  # Can be used by load balancers and uptime monitors to verify that the app is live.
  get "up" => "rails/health#show", as: :rails_health_check

  # Solid Queue の管理 UI（admin のみ）。
  # 認可は Admin::MissionControlBaseController#require_admin で実施
  # （config/initializers/mission_control_jobs.rb で base_controller_class に差し込み）。
  mount MissionControl::Jobs::Engine, at: "/jobs"

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

    # コスト単価などのアプリ全体設定（シングルトン）。admin 専用。
    resource :settings, only: [ :edit, :update ]

    # Redash 接続情報（API URL + 暗号化APIキー）の CRUD。トピック22。
    resources :redash_sources, except: [ :show ]
  end

  # BigQuery 接続管理（admin 専用）
  namespace :bigquery do
    resources :connections, except: [ :show ]
  end

  # Redash クエリ取り込み（トピック22）。ログインユーザーが Redash から
  # クエリ一覧を取得して複数選択し、BigQuery 接続を選んで一括 import する。
  # /redash_import/new で RedashSource を選び、/redash_import/:id/index_queries で
  # 一覧を表示し、/redash_import に POST で取り込みを実行する。
  resource :redash_import, only: [ :new, :create ] do
    member do
      get :index_queries
    end
  end

  # クエリエディタ（CodeMirror 6・保存クエリの CRUD）
  # dry-run（コスト保護★）: POST /queries/:query_id/dry_run。SQL 本文は
  # リクエストボディの現在のエディタ内容を受け取り、接続コンテキストのみ Query から得る。
  resources :queries do
    resource :dry_run, only: [ :create ], module: "queries"

    # 非同期実行（トピック10）: POST /queries/:query_id/executions で
    # QueryExecution を作成し SolidQueue に投入。最新成功実行の全件 CSV は
    # GET /queries/:query_id/executions/latest/csv で X-Sendfile 配信する。
    # GET /queries/:query_id/executions/:id は過去実行の結果テーブル再表示
    # （トピック17・トピック13フルオープンに合わせ全ユーザー閲覧可。存在しない
    # query_id / 当該クエリ配下に無い execution id は 404。create は所有者のみ）。
    resources :executions, only: [ :create, :show ], module: "queries" do
      get "latest/csv", to: "executions/csv_exports#show", on: :collection, as: :latest_csv
    end

    # 可視化（トピック11）: クエリ結果を Chart.js で描画する設定（軸・系列・
    # チャート種別・表示モード・counter）。1クエリ1可視化（has_one）。
    resource :visualization, only: [ :show, :update ]
  end

  # ダッシュボード（トピック12）。複数クエリの可視化（ウィジェット）を縦積み/
  # 1〜2カラムグリッドにまとめる。閲覧・編集は全ログインユーザーに許可（§4.9）。
  resources :dashboards do
    resources :widgets, only: [ :create, :destroy ]
    resource :widget_order, only: [ :update ]
  end

  # スキーマブラウザ（データセット→テーブル→カラムのツリー表示）
  get "schema_browser" => "schema_browsers#show", as: :schema_browser

  # スキーマキャッシュの手動更新（TTL を無視して再同期）
  resources :schema_caches, only: [] do
    collection do
      post :refresh
    end
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
