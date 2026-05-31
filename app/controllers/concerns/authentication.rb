module Authentication
  extend ActiveSupport::Concern

  included do
    helper_method :current_user, :logged_in?
  end

  private

  def current_user
    return @current_user if defined?(@current_user)

    @current_user = User.find_by(id: session[:user_id])
  end

  def logged_in?
    current_user.present?
  end

  def require_login
    return if logged_in?

    redirect_to new_session_path, alert: "ログインしてください。"
  end

  def require_admin
    require_login
    return if performed?

    redirect_to root_path, alert: "この操作には管理者権限が必要です。" unless current_user.admin?
  end
end
