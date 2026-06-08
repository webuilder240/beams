# Redash の `GET /api/queries/:id` レスポンス（Hash）を Beams 側の
# Query / QueryParameter 構造に変換する PORO（service クラス禁止規約のため
# `app/models/` 配下）。
#
# - 入力: パース済みの Redash クエリ JSON（Hash）
# - 出力: `#title` / `#sql_body` / `#parameters`（`[{ name:, type: }]`）/ `#warnings`
#
# 型マッピング（B4）と拡張記法検出（B7）はここで完結する。
class RedashQueryPayload
  # Redash type → Beams type のマッピング表（B4）。
  TYPE_MAPPING = {
    "text"      => :string,
    "number"    => :number,
    "date"      => :date,
    "date-range" => :date_range
  }.freeze

  # マップ結果が「対応 type に落ちるが警告を残す」もの。
  WARN_AND_MAP = {
    "datetime-local"             => :string,
    "datetime-with-seconds"      => :string,
    "datetime-range"             => :date_range,
    "datetime-range-with-seconds" => :date_range,
    "enum"                       => :string,
    "query"                      => :string
  }.freeze

  attr_reader :errors, :warnings

  def initialize(hash)
    @hash = hash.is_a?(Hash) ? hash : {}
    @errors = []
    @warnings = []
    @validated = false
  end

  def valid?
    @errors = []
    @errors << "name（タイトル）が空です" if title.blank?
    @errors << "query（SQL本文）が空です" if sql_body.blank?
    @validated = true
    @errors.empty?
  end

  def title
    @hash["name"].to_s
  end

  def sql_body
    @hash["query"].to_s
  end

  # Redash パラメータ定義を Beams の `[{ name:, type: }]` 配列にマップする。
  # 同時に warnings を追記する（同 instance を複数回呼んでも結果は安定）。
  def parameters
    @parameters ||= compute_parameters_and_warnings
  end

  # warnings を呼び出すために parameters を先に解決する。
  def warnings
    parameters # populates @warnings via side effect
    detect_template_warnings
    @warnings
  end

  private

  def compute_parameters_and_warnings
    redash_params = @hash.dig("options", "parameters") || []
    redash_params.each_with_object([]) do |param, acc|
      name = param["name"].to_s
      next if name.empty?

      type, warning = map_type(param["type"].to_s)
      @warnings << warning if warning
      acc << { name: name, type: type }
    end
  end

  def map_type(redash_type)
    if TYPE_MAPPING.key?(redash_type)
      [ TYPE_MAPPING[redash_type], nil ]
    elsif WARN_AND_MAP.key?(redash_type)
      [ WARN_AND_MAP[redash_type], "未対応の Redash 型 `#{redash_type}` を `#{WARN_AND_MAP[redash_type]}` にフォールバックしました" ]
    else
      [ :string, "未知の Redash 型 `#{redash_type}` を `string` にフォールバックしました" ]
    end
  end

  # SQL 本文に対する B7 拡張記法検出。重複追加を避けるため一度だけ動かす。
  def detect_template_warnings
    return if @template_warnings_detected

    sql = sql_body
    if sql.match?(/\{\{[^}]*\|[^}]*\}\}/)
      @warnings << "Redash のフィルタ式（`{{ ... | ... }}`）が検出されました。Beams では未対応のため、SQL 本文はそのまま保存します。"
    end
    if sql.match?(/\{%.*?%\}/m)
      @warnings << "Redash のテンプレートタグ（`{% ... %}`）が検出されました。Beams では未対応のため、SQL 本文はそのまま保存します。"
    end

    @template_warnings_detected = true
  end
end
