# frozen_string_literal: true

require "test_helper"

# トピック23 (B2): ApplicationController#set_current_user により、各リクエスト中に
# `Current.user` が `current_user` と一致することを検証する。
#
# 内部実装（特定アクションのモデル呼び出し）に依存しないよう、テスト専用の
# anonymous controller を ApplicationController から派生させ、最小の index アクションで
# before_action 適用後の `Current.user` を観測する。
class CurrentUserAssignmentTest < ActionController::TestCase
  # Anonymous controller derived from ApplicationController.
  class AnonymousController < ApplicationController
    def index
      render plain: "current_user_id=#{Current.user&.id}"
    end
  end

  tests AnonymousController

  setup do
    create_user # セットアップ誘導回避（User.any? を true にする）
    @routes = ActionDispatch::Routing::RouteSet.new
    @routes.draw { get "anonymous/index" => "current_user_assignment_test/anonymous#index" }
  end

  # --- ログイン中のとき ---
  test "リクエスト処理中に Current.user が current_user と一致する" do
    user = create_user(role: "member")
    session[:user_id] = user.id

    get :index

    assert_equal "current_user_id=#{user.id}", response.body
  end

  # --- 未ログインのとき ---
  test "Current.user は nil のままになる" do
    get :index

    assert_equal "current_user_id=", response.body
  end
end
