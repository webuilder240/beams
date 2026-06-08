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
  # SSRF ガード違反（不正スキーム、private/loopback IP、ホスト解決失敗、
  # IP リテラルの拒否帯への該当など）。
  #
  # M3: この例外の権威は `RedashSource` 側に置く。`RedashClient::ForbiddenURLError`
  # は互換 alias（`redash_client.rb` で再宣言）。
  class ForbiddenURLError < StandardError; end

  # SSRF ガード通過後の検査済みターゲット。
  # `RedashClient` は `ip` に対して TCP 接続を張り、`uri.hostname` を SNI/Host
  # ヘッダとして使うことで DNS rebinding を防ぐ（M1）。
  GuardedTarget = Struct.new(:uri, :ip, keyword_init: true)

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
  # 違反があれば `ForbiddenURLError` を raise する。
  # 正常時は `GuardedTarget(uri:, ip:)` を返す。`RedashClient` が
  # リクエスト直前に呼び出し、戻り値の `ip` に対して TCP 接続を張ることで
  # DNS rebinding（resolve 後に別 IP に切り替えるタイプの攻撃）を防ぐ（M1）。
  def self.guard_url!(url)
    uri = parse_uri(url)
    unless ALLOWED_SCHEMES.include?(uri.scheme)
      raise ForbiddenURLError, "URL のスキームは https のみ許可されています（指定: #{uri.scheme.inspect}）"
    end

    # S1: 角括弧つきホストを避けるため `host` ではなく `hostname` を使う。
    hostname = uri.hostname
    if hostname.blank?
      raise ForbiddenURLError, "URL にホスト名が含まれていません"
    end

    # S1: ホストが IP リテラルなら DNS を介さず直接帯域チェック。
    if (literal_ip = ip_for(hostname))
      check_forbidden!(literal_ip, hostname)
      return GuardedTarget.new(uri: uri, ip: hostname)
    end

    addresses = Resolv.getaddresses(hostname)
    if addresses.empty?
      raise ForbiddenURLError, "ホスト名を解決できませんでした: #{hostname}"
    end

    resolved_ip = nil
    addresses.each do |addr|
      ip = ip_for(addr)
      next if ip.nil?

      check_forbidden!(ip, addr)
      resolved_ip ||= addr
    end

    if resolved_ip.nil?
      raise ForbiddenURLError, "ホスト名から有効な IP を取得できませんでした: #{hostname}"
    end

    GuardedTarget.new(uri: uri, ip: resolved_ip)
  end

  # URL を `URI` にパースする。パース失敗時は `ForbiddenURLError` を raise。
  def self.parse_uri(url)
    URI.parse(url.to_s)
  rescue URI::InvalidURIError
    raise ForbiddenURLError, "URL の形式が不正です: #{url.inspect}"
  end

  # 文字列を `IPAddr` に変換する。IP として解釈できなければ nil。
  def self.ip_for(address)
    IPAddr.new(address)
  rescue IPAddr::InvalidAddressError
    nil
  end

  def self.check_forbidden!(ip, label)
    return unless FORBIDDEN_RANGES.any? { |range| range.include?(ip) }

    raise ForbiddenURLError,
          "プライベート/ループバック/メタデータ IP への接続は禁止されています: #{label}"
  end
  private_class_method :check_forbidden!

  private

  def url_must_pass_ssrf_guard
    return if url.blank?

    self.class.guard_url!(url)
  rescue ForbiddenURLError => e
    errors.add(:url, e.message)
  end
end
