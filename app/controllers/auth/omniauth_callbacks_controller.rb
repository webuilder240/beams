module Auth
  # OmniAuth コールバックの受け口（[[20-sso]]）。
  # 認証ミドルウェアが解決した `omniauth.auth` を `User.find_or_create_for_oauth`
  # に渡し、結果でセッションを作成する。
  class OmniauthCallbacksController < ApplicationController
    # 初回セットアップ未了状態でも OAuth コールバックは処理させる
    # （初回 admin は別経路 = setup wizard を使うのでここに来ることは通常ないが、
    # 万一来た場合にセットアップ画面へリダイレクトループしないよう skip する）。
    skip_before_action :redirect_to_setup_if_needed

    def google_oauth2
      handle_callback("google_oauth2")
    end

    def failure
      redirect_to new_session_path, alert: oauth_failure_message
    end

    # OmniAuth ミドルウェアが届かなかった場合のフォールバック（通常は到達しない）。
    def passthru
      render status: :not_found, plain: "Not found. Authentication passthru."
    end

    private

    def handle_callback(provider)
      auth = request.env["omniauth.auth"]
      user = User.find_or_create_for_oauth(
        provider: provider,
        uid: auth.uid,
        email: auth.info&.email
      )

      if user
        reset_session
        session[:user_id] = user.id
        redirect_to root_path, notice: "Google アカウントでログインしました。"
      else
        redirect_to new_session_path, alert: "このメールアドレスはログインを許可されていません。"
      end
    end

    def oauth_failure_message
      reason = params[:message].presence || "unknown"
      "Google ログインに失敗しました（#{reason}）。"
    end
  end
end
