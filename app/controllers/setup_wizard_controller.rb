class SetupWizardController < ApplicationController
  # ウィザードは初回起動誘導の対象外（リダイレクトループ防止）。
  skip_before_action :redirect_to_setup_if_needed

  # 完了済み（ユーザーが 1 件以上）なら入口（index/step1）からはルートに戻す。
  # step2 以降は step1 完了済み（=User 存在）が前提のため対象外。
  before_action :redirect_to_root_if_completed, only: [ :index, :step1, :create_step1 ]
  # 各ステップ開始前に前ステップの完了を確認する。
  before_action :require_step1_completed, only: [ :step2, :create_step2, :step3, :step4, :create_step4 ]
  before_action :require_step2_completed, only: [ :step3, :step4, :create_step4 ]

  # GET /setup — ウィザードの入口。最初のステップに送る。
  def index
    redirect_to setup_step1_path
  end

  # GET /setup/step1 — admin 作成フォーム
  def step1
    @user = User.new
  end

  # POST /setup/step1 — admin User を作成しセッションを確立して step2 へ
  def create_step1
    @user = User.new(step1_params.merge(role: "admin"))

    if @user.save
      reset_session
      session[:user_id] = @user.id
      redirect_to setup_step2_path
    else
      render :step1, status: :unprocessable_content
    end
  end

  # GET /setup/step2 — BigQuery 接続登録フォーム
  def step2
    @connection = Bigquery::Connection.new
  end

  # POST /setup/step2 — 接続を作成して step3 へ（コスト上限は step4 で設定）
  def create_step2
    @connection = Bigquery::Connection.new(step2_params)

    if @connection.save
      redirect_to setup_step3_path
    else
      render :step2, status: :unprocessable_content
    end
  end

  # GET /setup/step3 — 接続テストの診断結果を表示
  def step3
    @connection = Bigquery::Connection.first
    @result = @connection.test_connection
  end

  # GET /setup/step4 — コスト上限設定フォーム
  def step4
    @connection = Bigquery::Connection.first
  end

  # POST /setup/step4 — コスト上限を保存（空ならスキップ）してウィザード完了
  def create_step4
    connection = Bigquery::Connection.first
    connection.update(maximum_bytes_billed: step4_params[:maximum_bytes_billed].presence)

    redirect_to root_path, notice: "セットアップが完了しました。"
  end

  private

  def redirect_to_root_if_completed
    redirect_to root_path if User.any?
  end

  def require_step1_completed
    redirect_to setup_step1_path if User.none?
  end

  def require_step2_completed
    redirect_to setup_step2_path if Bigquery::Connection.none?
  end

  def step1_params
    params.expect(user: [ :email, :password, :password_confirmation ])
  end

  def step2_params
    params.expect(bigquery_connection: [ :name, :project_id, :service_account_json ])
  end

  def step4_params
    params.expect(bigquery_connection: [ :maximum_bytes_billed ])
  end
end
