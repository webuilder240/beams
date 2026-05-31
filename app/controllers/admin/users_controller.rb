module Admin
  class UsersController < ApplicationController
    before_action :require_admin
    before_action :set_user, only: [ :edit, :update, :destroy, :reset_password ]

    def index
      @users = User.order(:email)
    end

    def new
      @user = User.new(role: "member")
    end

    def create
      @user = User.new(user_params)

      if @user.save
        redirect_to admin_users_path, notice: "ユーザーを作成しました。"
      else
        render :new, status: :unprocessable_content
      end
    end

    def edit
    end

    def update
      if @user.update(user_update_params)
        redirect_to admin_users_path, notice: "ユーザーを更新しました。"
      else
        render :edit, status: :unprocessable_content
      end
    end

    def destroy
      @user.destroy
      redirect_to admin_users_path, notice: "ユーザーを削除しました。"
    end

    def reset_password
      new_password = password_params[:password]

      if new_password.blank?
        @user.errors.add(:password, :blank)
        flash.now[:alert] = "新しいパスワードを入力してください。"
        return render :edit, status: :unprocessable_content
      end

      if @user.update(password: new_password)
        redirect_to admin_users_path, notice: "パスワードを再発行しました。"
      else
        render :edit, status: :unprocessable_content
      end
    end

    private

    def set_user
      @user = User.find(params[:id])
    end

    def user_params
      params.expect(user: [ :email, :password, :role ])
    end

    # 更新時はパスワード空欄を許容（has_secure_password が空文字を無視）
    def user_update_params
      params.expect(user: [ :email, :role ])
    end

    def password_params
      params.expect(user: [ :password ])
    end
  end
end
