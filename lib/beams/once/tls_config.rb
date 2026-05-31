# frozen_string_literal: true

module Beams
  module Once
    # TLS 終端越し運用の有効判定を担う PORO。
    #
    # ONCE 配布では Thruster に `TLS_DOMAIN` を与えたときだけ Let's Encrypt で
    # 証明書を取得し HTTPS(443) 終端する。production.rb はこの PORO を呼び、
    # `TLS_DOMAIN` がある場合のみ `assume_ssl` / `force_ssl` / `ssl_options` を
    # 設定する（環境設定ファイルに分岐ロジックを直書きしない）。
    #
    # ENV は注入可能（`env:` キーワード）でテスト可能。
    class TlsConfig
      # https リダイレクトから除外する health check パス。
      HEALTH_CHECK_PATH = "/up"

      def initialize(env: ENV)
        @domain = env["TLS_DOMAIN"].to_s.strip
      end

      # TLS 終端越し運用を有効化すべきか（= TLS_DOMAIN が設定されているか）。
      def enabled?
        !@domain.empty?
      end

      # force_ssl 用の ssl_options。health check（/up）を https リダイレクトから除外する。
      def ssl_options
        { redirect: { exclude: ->(request) { request.path == HEALTH_CHECK_PATH } } }
      end
    end
  end
end
