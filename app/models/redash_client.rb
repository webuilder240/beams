require "net/http"
require "json"
require "uri"

# Redash REST API クライアント PORO（service クラス禁止規約のため `app/models/` 配下）。
# `RedashSource` を 1 つ受け取り、`#list_queries` / `#fetch_query` を提供する。
#
# - 認証ヘッダ: `Authorization: Key <api_key>`
# - タイムアウト: open/read 共に 5 秒
# - リダイレクト追従なし（1 リクエスト = 1 接続）
# - SSRF ガード: リクエスト直前に `RedashSource.guard_url!` で URL を検査
#
# 失敗は例外クラスで明示する（`Unauthorized` / `NotFound` / `ServerError`
# / `Timeout` / `ForbiddenURLError`）。呼び出し側はこれらをユーザー向けメッセージへ
# マップする。
class RedashClient
  # 共通の基底クラス（呼び出し側で一括 rescue できるように）。
  class Error < StandardError; end

  # 401 Unauthorized（APIキー不正）
  class Unauthorized < Error; end

  # 404 Not Found（クエリ ID 不在など）
  class NotFound < Error; end

  # 5xx Server Error / 想定外ステータス
  class ServerError < Error; end

  # ソケット/接続タイムアウト
  class Timeout < Error; end

  # SSRF ガード違反（http 等の不正スキーム、private/loopback IP、ホスト解決失敗）
  class ForbiddenURLError < Error; end

  OPEN_TIMEOUT_SEC = 5
  READ_TIMEOUT_SEC = 5

  def initialize(redash_source)
    @redash_source = redash_source
  end

  # `GET /api/queries` でクエリ一覧を取得する（ページネーション込み）。
  # 戻り値は Redash 公式レスポンス（`{ "count":, "page":, "page_size":, "results": [...] }`）。
  def list_queries(page: 1, page_size: 25)
    request(:get, "/api/queries", page: page, page_size: page_size)
  end

  # `GET /api/queries/:id` でクエリ詳細を取得する（パース済み Hash）。
  def fetch_query(id)
    request(:get, "/api/queries/#{Integer(id)}")
  end

  private

  attr_reader :redash_source

  # Net::HTTP ベースの 1 リクエスト実装。リダイレクトは追従しない。
  def request(method, path, **query_params)
    raise ArgumentError, "未対応のメソッド: #{method}" unless method == :get

    target_url = build_url(path, query_params)
    uri = RedashSource.guard_url!(target_url)

    response = perform(uri)
    handle_response(response)
  rescue Net::OpenTimeout, Net::ReadTimeout, Errno::ETIMEDOUT
    raise Timeout, "Redash サーバへの接続がタイムアウトしました（#{READ_TIMEOUT_SEC} 秒）"
  end

  def build_url(path, query_params)
    base = URI.parse(redash_source.url)
    base.path = path
    base.query = URI.encode_www_form(query_params) if query_params.any?
    base.to_s
  end

  def perform(uri)
    http = Net::HTTP.new(uri.host, uri.port)
    http.use_ssl = (uri.scheme == "https")
    http.open_timeout = OPEN_TIMEOUT_SEC
    http.read_timeout = READ_TIMEOUT_SEC

    request_path = uri.path
    request_path = "#{request_path}?#{uri.query}" if uri.query
    req = Net::HTTP::Get.new(request_path)
    req["Authorization"] = "Key #{redash_source.api_key}"
    req["Accept"] = "application/json"

    http.request(req)
  end

  def handle_response(response)
    case response.code.to_i
    when 200..299
      parse_json(response.body)
    when 401, 403
      raise Unauthorized, "Redash の API キーが無効です（HTTP #{response.code}）"
    when 404
      raise NotFound, "Redash 上にリソースが存在しません（HTTP 404）"
    when 500..599
      raise ServerError, "Redash サーバ側でエラーが発生しました（HTTP #{response.code}）"
    else
      raise ServerError, "Redash から想定外のレスポンスを受信しました（HTTP #{response.code}）"
    end
  end

  def parse_json(body)
    JSON.parse(body.to_s)
  rescue JSON::ParserError => e
    raise ServerError, "Redash のレスポンスが JSON として解釈できません: #{e.message}"
  end
end
