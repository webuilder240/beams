require "rails_helper"

RSpec.describe "Current.user assignment in requests", type: :request do
  let(:user) { create(:user, :member, password: "password") }

  def login_as(who, password: "password")
    post session_path, params: { email: who.email, password: password }
  end

  before { create(:user) } # セットアップ誘導回避

  it "ログイン中のリクエスト処理中に Current.user が current_user と一致する" do
    login_as(user)

    captured = nil
    # コントローラのアクションに入る前に Current.user がセットされていることを
    # before_action のフック挙動で検証する。
    allow(Dashboard).to receive(:title_matching) do |_q|
      captured = Current.user
      raise "stop here" # ビュー描画前で止める
    end

    expect { get dashboards_path }.to raise_error("stop here")
    expect(captured).to eq(user)
  end

  it "リクエスト終了後に Current.user がリセットされている" do
    login_as(user)
    allow(Dashboard).to receive(:title_matching).and_return(Dashboard.none)
    begin
      get dashboards_path
    rescue StandardError
      # ビュー描画エラーは無視
    end
    expect(Current.user).to be_nil
  end
end
