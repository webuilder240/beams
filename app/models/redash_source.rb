require "resolv"
require "ipaddr"
require "uri"

# Redash サーバの接続情報。URL + 暗号化された API キー + 表示名。
# API キーは Active Record Encryption で暗号化して保存する
# （`Bigquery::Connection.service_account_json` と同方式）。
#
# SSRF ガード（B8）はバリデーション（作成時）と `RedashClient` のリクエスト直前
# の両方で行う。両方が同じ判定ロジック（`guard_url!`）を共有する。
class RedashSource < ApplicationRecord
  # 拒否する IP アドレス帯（B8 詳細表）。
  # loopback / private / link-local / ULA / multicast を全て弾く。
  FORBIDDEN_RANGES = [
    IPAddr.new("127.0.0.0/8"),       # IPv4 loopback
    IPAddr.new("10.0.0.0/8"),        # IPv4 private
    IPAddr.new("172.16.0.0/12"),     # IPv4 private
    IPAddr.new("192.168.0.0/16"),    # IPv4 private
    IPAddr.new("169.254.0.0/16"),    # IPv4 link-local（AWS/GCP メタデータ含む）
    IPAddr.new("224.0.0.0/4"),       # IPv4 multicast
    IPAddr.new("0.0.0.0/8"),         # IPv4 unspecified
    IPAddr.new("::1/128"),           # IPv6 loopback
    IPAddr.new("fc00::/7"),          # IPv6 ULA（unique local）
    IPAddr.new("fe80::/10"),         # IPv6 link-local
    IPAddr.new("ff00::/8")           # IPv6 multicast
  ].freeze

  ALLOWED_SCHEMES = %w[https].freeze

  encrypts :api_key

  validates :name, presence: true, uniqueness: true
  validates :url,     presence: true
  validates :api_key, presence: true
  validate :url_must_pass_ssrf_guard

  # URL のスキーム / ホスト / 解決後 IP を SSRF 観点で検査する。
  # 違反があれば例外（`RedashClient::ForbiddenURLError`）を raise する。
  # 正常時は `URI` を返す。`RedashClient` がリクエスト直前に呼び出す。
  def self.guard_url!(url)
    uri = parse_uri(url)
    unless ALLOWED_SCHEMES.include?(uri.scheme)
      raise RedashClient::ForbiddenURLError, "URL のスキームは https のみ許可されています（指定: #{uri.scheme.inspect}）"
    end
    if uri.host.blank?
      raise RedashClient::ForbiddenURLError, "URL にホスト名が含まれていません"
    end

    addresses = Resolv.getaddresses(uri.host)
    if addresses.empty?
      raise RedashClient::ForbiddenURLError, "ホスト名を解決できませんでした: #{uri.host}"
    end

    addresses.each do |addr|
      ip = ip_for(addr)
      next if ip.nil?

      if FORBIDDEN_RANGES.any? { |range| range.include?(ip) }
        raise RedashClient::ForbiddenURLError,
              "プライベート/ループバック/メタデータ IP への接続は禁止されています: #{addr}"
      end
    end

    uri
  end

  # URL を `URI` にパースする。パース失敗時は `RedashClient::ForbiddenURLError` を raise。
  def self.parse_uri(url)
    URI.parse(url.to_s)
  rescue URI::InvalidURIError
    raise RedashClient::ForbiddenURLError, "URL の形式が不正です: #{url.inspect}"
  end

  # 文字列を `IPAddr` に変換する。IP として解釈できなければ nil。
  def self.ip_for(address)
    IPAddr.new(address)
  rescue IPAddr::InvalidAddressError
    nil
  end

  private

  def url_must_pass_ssrf_guard
    return if url.blank?

    self.class.guard_url!(url)
  rescue RedashClient::ForbiddenURLError => e
    errors.add(:url, e.message)
  end
end
