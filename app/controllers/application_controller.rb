class ApplicationController < ActionController::Base
  include Authentication

  # Only allow modern browsers supporting webp images, web push, badges, import maps, CSS nesting, and CSS :has.
  allow_browser versions: :modern

  # Changes to the importmap will invalidate the etag for HTML responses
  stale_when_importmap_changes

  # 初回起動（ユーザー 0 件）を検知し、セットアップウィザードに誘導する。
  # ウィザード自身のコントローラでは skip する（リダイレクトループ防止）。
  before_action :redirect_to_setup_if_needed

  private

  def redirect_to_setup_if_needed
    return if User.any?

    redirect_to setup_step1_path
  end
end
