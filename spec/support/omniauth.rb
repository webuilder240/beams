# OmniAuth テストモードのセットアップ（[[20-sso]]）。
# request / system spec から `mock_oauth_response!` で成功レスポンスを差し込み、
# `mock_oauth_failure!` で失敗を再現できる。
OmniAuth.config.test_mode = true
OmniAuth.config.logger = Logger.new(IO::NULL)

module OmniAuthSpecHelpers
  def mock_oauth_response!(provider: "google_oauth2", uid: "test-uid-123", email: "test@example.com")
    OmniAuth.config.mock_auth[provider.to_sym] = OmniAuth::AuthHash.new(
      provider: provider,
      uid: uid,
      info: OmniAuth::AuthHash::InfoHash.new(email: email)
    )
  end

  def mock_oauth_failure!(provider: "google_oauth2", reason: :invalid_credentials)
    OmniAuth.config.mock_auth[provider.to_sym] = reason
  end

  def reset_oauth_mocks!
    OmniAuth.config.mock_auth[:google_oauth2] = nil
  end
end

RSpec.configure do |config|
  config.include OmniAuthSpecHelpers
  config.after(:each) { reset_oauth_mocks! }
end
