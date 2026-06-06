# Redash クエリ取り込み（トピック22）。
# - `new`: 登録済み RedashSource の選択フォーム
# - `index_queries`: 選んだ RedashSource から `RedashClient#list_queries` でクエリ一覧を表示
# - `create`: チェック済みクエリ ID 群を `fetch_query` → `RedashQueryPayload` →
#   `current_user.queries.create!` のループで取り込み、成功/失敗/警告を結果画面に表示する
class RedashImportsController < ApplicationController
  before_action :require_login

  # 取り込み結果 1 件分の値オブジェクト（成功/失敗/警告/作成された Query を一括で保持）。
  ImportResult = Struct.new(:redash_id, :title, :status, :query, :warnings, :error_message, keyword_init: true)

  # S4: ユーザー向けフラッシュは固定文言。詳細（例外メッセージ・内部 IP 等）は
  # コントローラから view に渡さずに Rails.logger に記録する。
  FLASH_UNAUTHORIZED = "Redash の API キーが無効です。".freeze
  FLASH_TIMEOUT      = "Redash サーバへの接続がタイムアウトしました。".freeze
  FLASH_SERVER_ERROR = "Redash サーバ側でエラーが発生しました。".freeze
  FLASH_FORBIDDEN    = "Redash サーバが許可されていません。".freeze
  FLASH_NOT_FOUND_SOURCE = "Redash 接続が見つかりません。".freeze
  FLASH_NOT_FOUND_BOTH   = "Redash 接続または BigQuery 接続が見つかりません。".freeze
  FLASH_GENERIC      = "Redash 接続でエラーが発生しました。".freeze

  def new
    @redash_sources = RedashSource.order(:name)
  end

  def index_queries
    @redash_source = RedashSource.find(params[:redash_source_id])
    @bigquery_connections = Bigquery::Connection.order(:name)
    page = (params[:page].presence || 1).to_i
    page = 1 if page < 1

    client = RedashClient.new(@redash_source)
    response = client.list_queries(page: page, page_size: 50)
    @queries = response["results"] || []
    @page = response["page"] || page
    @page_size = response["page_size"]
    @count = response["count"]
  rescue ActiveRecord::RecordNotFound
    redirect_to new_redash_import_path, alert: FLASH_NOT_FOUND_SOURCE
  rescue RedashClient::Unauthorized => e
    log_redash_error(e)
    redirect_to new_redash_import_path, alert: FLASH_UNAUTHORIZED
  rescue RedashSource::ForbiddenURLError => e
    log_redash_error(e)
    redirect_to new_redash_import_path, alert: FLASH_FORBIDDEN
  rescue RedashClient::Timeout => e
    log_redash_error(e)
    redirect_to new_redash_import_path, alert: FLASH_TIMEOUT
  rescue RedashClient::ServerError => e
    log_redash_error(e)
    redirect_to new_redash_import_path, alert: FLASH_SERVER_ERROR
  rescue StandardError => e
    log_redash_error(e)
    redirect_to new_redash_import_path, alert: FLASH_GENERIC
  end

  def create
    @redash_source = RedashSource.find(params[:redash_source_id])

    if params[:bigquery_connection_id].blank?
      return redirect_to new_redash_import_path,
                         alert: "取り込み先の BigQuery 接続を選択してください。"
    end

    query_ids = Array(params[:query_ids]).reject(&:blank?)
    if query_ids.empty?
      return redirect_to index_queries_redash_import_path(redash_source_id: @redash_source.id),
                         alert: "取り込むクエリを 1 つ以上選択してください。"
    end

    @bigquery_connection = Bigquery::Connection.find(params[:bigquery_connection_id])
    client = RedashClient.new(@redash_source)
    @results = query_ids.map { |id| import_one(client, id) }
    @success_count = @results.count { |r| r.status == :success }
    @failure_count = @results.count { |r| r.status == :failure }
    @warning_count = @results.count { |r| r.warnings.present? }
  rescue ActiveRecord::RecordNotFound
    redirect_to new_redash_import_path, alert: FLASH_NOT_FOUND_BOTH
  end

  private

  # 1 クエリ分の取り込み。例外は捕捉して ImportResult に変換し、ループを継続させる。
  # M2: Integer(redash_query_id) の ArgumentError や、想定外の StandardError も
  # 全て :failure として握りつぶしてループを継続させる（部分失敗の局所化）。
  def import_one(client, redash_query_id)
    # M2: 非数値 ID は最初に捕捉して :failure にする（client.fetch_query が
    # Integer() で ArgumentError を上げるため）。
    int_id = Integer(redash_query_id, 10)

    detail = client.fetch_query(int_id)
    payload = RedashQueryPayload.new(detail)

    unless payload.valid?
      return ImportResult.new(
        redash_id: redash_query_id, title: payload.title.presence || "(タイトルなし)",
        status: :failure, warnings: [],
        error_message: payload.errors.join(" / ")
      )
    end

    query = current_user.queries.create!(
      title: payload.title,
      sql_body: payload.sql_body,
      bigquery_connection: @bigquery_connection
    )

    warnings = payload.warnings.dup
    warnings.concat(apply_parameter_types(query, payload.parameters))

    ImportResult.new(
      redash_id: redash_query_id, title: payload.title,
      status: :success, query: query, warnings: warnings
    )
  rescue ArgumentError => e
    log_redash_error(e)
    failure_result(redash_query_id, "クエリ ID が不正です: #{redash_query_id.inspect}")
  rescue RedashClient::NotFound
    failure_result(redash_query_id, "Redash 上にこのクエリ ID は存在しません")
  rescue RedashClient::Unauthorized
    failure_result(redash_query_id, "Redash の API キーが無効です")
  rescue RedashSource::ForbiddenURLError => e
    log_redash_error(e)
    failure_result(redash_query_id, "Redash サーバが許可されていません")
  rescue RedashClient::Timeout
    failure_result(redash_query_id, "Redash サーバへの接続がタイムアウトしました")
  rescue RedashClient::ServerError => e
    log_redash_error(e)
    failure_result(redash_query_id, "Redash サーバ側でエラーが発生しました")
  rescue ActiveRecord::RecordInvalid => e
    log_redash_error(e)
    failure_result(redash_query_id, "Beams 側で保存に失敗しました")
  rescue StandardError => e
    # M2: 最終キャッチ。1 件の予期せぬ例外でループ全体が落ちないようにする。
    log_redash_error(e)
    failure_result(redash_query_id, "予期しないエラーが発生しました")
  end

  def failure_result(redash_query_id, error_message)
    ImportResult.new(
      redash_id: redash_query_id,
      title: "(ID #{redash_query_id})",
      status: :failure,
      warnings: [],
      error_message: error_message
    )
  end

  # Query#sync_parameters! は SQL の `{{ name }}` から型注釈なしのパラメータを
  # すべて `string` で同期する。Redash 側で明示された型は型情報がより豊富なので、
  # 作成後に Redash 由来の型で上書きする（SQL 本文には触れない: B7）。
  #
  # S2: 型情報があるのに SQL 本文に出現していないパラメータ
  # （例: `{{ name | json_encode }}` だけのフィルタ式しかない、または別名）は
  # 警告として収集して返す。`query_parameters` の自動作成はしない。
  def apply_parameter_types(query, parameters)
    warnings = []
    parameters.each do |spec|
      param = query.query_parameters.find_by(name: spec[:name])
      if param.nil?
        warnings << "パラメータ '#{spec[:name]}' (#{spec[:type]}) は SQL 本文に出現していないため適用されませんでした"
        next
      end
      param.update!(param_type: spec[:type].to_s)
    end
    warnings
  end

  def log_redash_error(exception)
    Rails.logger.warn(
      "[RedashImport] #{exception.class.name}: #{exception.message}"
    )
  end
end
