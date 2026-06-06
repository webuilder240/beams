# Redash クエリ取り込み（トピック22）。
# - `new`: 登録済み RedashSource の選択フォーム
# - `index_queries`: 選んだ RedashSource から `RedashClient#list_queries` でクエリ一覧を表示
# - `create`: チェック済みクエリ ID 群を `fetch_query` → `RedashQueryPayload` →
#   `current_user.queries.create!` のループで取り込み、成功/失敗/警告を結果画面に表示する
class RedashImportsController < ApplicationController
  before_action :require_login

  # 取り込み結果 1 件分の値オブジェクト（成功/失敗/警告/作成された Query を一括で保持）。
  ImportResult = Struct.new(:redash_id, :title, :status, :query, :warnings, :error_message, keyword_init: true)

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
    redirect_to new_redash_import_path, alert: "Redash 接続が見つかりません。"
  rescue RedashClient::Unauthorized
    redirect_to new_redash_import_path, alert: "Redash の API キーが無効です。"
  rescue RedashClient::ForbiddenURLError => e
    redirect_to new_redash_import_path, alert: "Redash の URL が不正です（#{e.message}）。"
  rescue RedashClient::Timeout
    redirect_to new_redash_import_path, alert: "Redash サーバへの接続がタイムアウトしました。"
  rescue RedashClient::ServerError => e
    redirect_to new_redash_import_path, alert: "Redash サーバでエラーが発生しました（#{e.message}）。"
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
    redirect_to new_redash_import_path, alert: "Redash 接続または BigQuery 接続が見つかりません。"
  end

  private

  # 1 クエリ分の取り込み。例外は捕捉して ImportResult に変換し、ループを継続させる。
  def import_one(client, redash_query_id)
    detail = client.fetch_query(redash_query_id)
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

    apply_parameter_types(query, payload.parameters)

    ImportResult.new(
      redash_id: redash_query_id, title: payload.title,
      status: :success, query: query, warnings: payload.warnings
    )
  rescue RedashClient::NotFound
    ImportResult.new(redash_id: redash_query_id, title: "(ID #{redash_query_id})",
                     status: :failure, warnings: [],
                     error_message: "Redash 上にこのクエリ ID は存在しません")
  rescue RedashClient::Unauthorized
    ImportResult.new(redash_id: redash_query_id, title: "(ID #{redash_query_id})",
                     status: :failure, warnings: [],
                     error_message: "Redash の API キーが無効です")
  rescue RedashClient::ForbiddenURLError => e
    ImportResult.new(redash_id: redash_query_id, title: "(ID #{redash_query_id})",
                     status: :failure, warnings: [],
                     error_message: "URL ガード違反: #{e.message}")
  rescue RedashClient::Timeout
    ImportResult.new(redash_id: redash_query_id, title: "(ID #{redash_query_id})",
                     status: :failure, warnings: [],
                     error_message: "Redash サーバへの接続がタイムアウトしました")
  rescue RedashClient::ServerError => e
    ImportResult.new(redash_id: redash_query_id, title: "(ID #{redash_query_id})",
                     status: :failure, warnings: [],
                     error_message: "Redash サーバエラー: #{e.message}")
  rescue ActiveRecord::RecordInvalid => e
    ImportResult.new(redash_id: redash_query_id, title: "(ID #{redash_query_id})",
                     status: :failure, warnings: [],
                     error_message: "Beams 側で保存に失敗しました: #{e.message}")
  end

  # Query#sync_parameters! は SQL の `{{ name }}` から型注釈なしのパラメータを
  # すべて `string` で同期する。Redash 側で明示された型は型情報がより豊富なので、
  # 作成後に Redash 由来の型で上書きする（SQL 本文には触れない: B7）。
  def apply_parameter_types(query, parameters)
    parameters.each do |spec|
      param = query.query_parameters.find_by(name: spec[:name])
      param&.update!(param_type: spec[:type].to_s)
    end
  end
end
