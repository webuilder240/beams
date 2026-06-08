require "net/http"
require "openssl"
require "json"
require "uri"

# Redash REST API クライアント PORO（service クラス禁止規約のため `app/models/` 配下）。
# `RedashSource` を 1 つ受け取り、`#list_queries` / `#fetch_query` を提供する。
#
# - 認証ヘッダ: `Authorization: Key <api_key>`
# - タイムアウト: open/read 共に 5 秒
# - リダイレクト追従なし（1 リクエスト = 1 接続）
# - SSRF ガード: リクエスト直前に `RedashSource.guard_url!` で URL を検査し、
#   返ってきた `GuardedTarget#ip` に対してのみ TCP 接続を張る（M1: DNS rebinding 防止）。
#   SNI と Host ヘッダは `uri.hostname` に固定し、TLS 検証は VERIFY_PEER を維持する。
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

  # M3: 例外の権威は `RedashSource::ForbiddenURLError` 側に移した。
  # 既存呼び出し側との後方互換を保つため、ここで定数 alias を貼る。
  ForbiddenURLError = RedashSource::ForbiddenURLError

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
    target = RedashSource.guard_url!(target_url)

    response = perform(target)
    handle_response(response)
  rescue Net::OpenTimeout, Net::ReadTimeout, Errno::ETIMEDOUT
    raise Timeout, "Redash サーバへの接続がタイムアウトしました（#{READ_TIMEOUT_SEC} 秒）"
  end

  # S5: source.url にクエリ文字列（?leak=token 等）が混入していても、
  # ここで明示的に nil クリアしてから組み立てる。
  def build_url(path, query_params)
    base = URI.parse(redash_source.url)
    base.path = path
    base.query = nil
    base.query = URI.encode_www_form(query_params) if query_params.any?
    base.to_s
  end

  # M1: guard_url! で確定した安全 IP に対して TCP 接続を張る。
  # `Net::HTTP.new` 自体にはホスト名を渡し、`http.ipaddr=` で実接続先を IP に固定する。
  # これにより:
  #   - Host ヘッダ / SNI / 証明書検証用ホスト名はホスト名のままとなり、TLS 検証
  #     （VERIFY_PEER）を壊さない
  #   - 名前解決のタイミングで安全と確認した IP にしか接続が行かない（DNS rebinding 防止）
  def perform(target)
    uri = target.uri
    http = Net::HTTP.new(uri.hostname, uri.port)
    http.ipaddr = target.ip if http.respond_to?(:ipaddr=)
    http.use_ssl = (uri.scheme == "https")
    if http.use_ssl?
      http.verify_mode = OpenSSL::SSL::VERIFY_PEER
    end
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
