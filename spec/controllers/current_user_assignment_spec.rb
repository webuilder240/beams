require "rails_helper"

# トピック23 (B2): ApplicationController#set_current_user により、各リクエスト中に
# `Current.user` が `current_user` と一致することを検証する。
#
# 内部実装（特定アクションのモデル呼び出し）に依存しないよう、テスト専用の
# anonymous controller を ApplicationController から派生させ、最小の index アクションで
# before_action 適用後の `Current.user` を観測する。
RSpec.describe ApplicationController, type: :controller do
  controller(ApplicationController) do
    def index
      render plain: "current_user_id=#{Current.user&.id}"
    end
  end

  before do
    create(:user) # セットアップ誘導回避（User.any? を true にする）
    routes.draw { get "anonymous/index" => "anonymous#index" }
  end

  context "ログイン中のとき" do
    let(:user) { create(:user, :member) }

    it "リクエスト処理中に Current.user が current_user と一致する" do
      session[:user_id] = user.id

      get :index

      expect(response.body).to eq("current_user_id=#{user.id}")
    end
  end

  context "未ログインのとき" do
    it "Current.user は nil のままになる" do
      get :index

      expect(response.body).to eq("current_user_id=")
    end
  end
end
