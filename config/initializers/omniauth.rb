# Google OAuth ログイン（トピック20 / SSO）
#
# `GOOGLE_OAUTH_CLIENT_ID` / `GOOGLE_OAUTH_CLIENT_SECRET` が設定されている時のみ
# `:google_oauth2` プロバイダを登録する。未設定の環境では OmniAuth ミドルウェアは
# 何も提供しないので、自前のメール+パスワード認証だけで運用される（B7-B）。
Rails.application.config.middleware.use OmniAuth::Builder do
  if Rails.env.test?
    # テスト時は OmniAuth.config.test_mode = true と `mock_auth` で
    # 実 Google 通信なしに認証フローを検証する。provider 登録は必要。
    provider :google_oauth2, "test-client-id", "test-client-secret"
  elsif ENV["GOOGLE_OAUTH_CLIENT_ID"].present? && ENV["GOOGLE_OAUTH_CLIENT_SECRET"].present?
    provider :google_oauth2,
             ENV["GOOGLE_OAUTH_CLIENT_ID"],
             ENV["GOOGLE_OAUTH_CLIENT_SECRET"],
             {
               scope: "email,profile",
               prompt: "select_account"
             }
  end
end

# サードパーティ provider への遷移失敗時のメッセージを日本語化のためにそのまま使用する。
OmniAuth.config.on_failure = proc { |env|
  OmniAuth::FailureEndpoint.new(env).redirect_to_failure
}

# SSO 有効化フラグを `Rails.configuration.x.sso_enabled` に一元化する（finding D）。
# view / spec はこのフラグだけを見る。ENV を読むのはこの initializer の 1 箇所のみ。
# test 環境では mock 認証フローを動かすため常に true で、必要に応じてテスト側で
# 一時的に false にして「未設定時の表示」を検証する。
Rails.configuration.x.sso_enabled =
  Rails.env.test? ||
  (ENV["GOOGLE_OAUTH_CLIENT_ID"].present? && ENV["GOOGLE_OAUTH_CLIENT_SECRET"].present?)
