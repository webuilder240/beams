# frozen_string_literal: true

module Beams
  module Once
    # Beams::Once::SslMode encapsulates the ONCE platform's SSL convention.
    #
    # ONCE terminates TLS automatically in front of the Beams container.
    # To opt out (e.g. when ONCE is not used or local development), the
    # operator passes `DISABLE_SSL=true`. Any other value (including unset
    # and empty string) keeps SSL enforcement enabled — `assume_ssl` and
    # `force_ssl` should be turned on in production, while `/up` is excluded
    # from the https redirect so the ONCE health check (and local probes
    # over plain HTTP) continue to receive 200 OK without a 301 hop.
    class SslMode
      # `/up` exclusion is value-stable across requests, so we freeze the
      # options hash once at load time rather than rebuilding it per request.
      SSL_OPTIONS = {
        redirect: { exclude: ->(request) { request.path == "/up" } }
      }.freeze

      def initialize(env: ENV)
        @env = env
      end

      # ONCE 規約に厳密準拠: "true" 以外（未設定 / 空文字 / 任意の文字列）は SSL 有効。
      def enabled?
        @env["DISABLE_SSL"] != "true"
      end

      def ssl_options
        SSL_OPTIONS
      end
    end
  end
end
