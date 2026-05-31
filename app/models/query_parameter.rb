require "date"

# クエリの `{{ name }}` パラメータ定義。`Query#sync_parameters!` が SQL から
# パースして同期する。値は BigQuery ネイティブパラメータ（`@name`）として
# バインドされ、SQL への文字列連結は一切行わない（SQL インジェクション排除）。
class QueryParameter < ApplicationRecord
  # 対応する型（DB には `param_type` に文字列で保存する）。
  SUPPORTED_TYPES = %i[string number date date_range].freeze

  belongs_to :query

  validates :name,
            presence: true,
            format: { with: /\A\w+\z/, message: "は英数字とアンダースコアのみ使用できます" },
            uniqueness: { scope: :query_id }
  validates :param_type, presence: true, inclusion: { in: SUPPORTED_TYPES.map(&:to_s) }

  # 入力値を BigQuery にバインドできる型付き値へ変換する。
  # 文字列連結は行わず、BigQuery Ruby SDK がネイティブパラメータとして扱える
  # Ruby オブジェクト（String / Integer / Float / Date / Hash）を返す。
  # 不正な値（数値欄に文字列・不正な日付など）は ArgumentError を送出する。
  def to_bigquery_param(value)
    case param_type
    when "string"     then value.to_s
    when "number"     then cast_number(value)
    when "date"       then cast_date(value)
    when "date_range" then cast_date_range(value)
    else
      raise ArgumentError, "未対応の param_type: #{param_type.inspect}"
    end
  end

  # この定義が展開する BigQuery バインド名の一覧。
  # `date_range` は `@name_start` / `@name_end` の 2 つに展開される。
  def bigquery_param_names
    if param_type == "date_range"
      [ "#{name}_start", "#{name}_end" ]
    else
      [ name ]
    end
  end

  private

  def cast_number(value)
    string = value.to_s.strip
    raise ArgumentError, "数値ではありません: #{value.inspect}" if string.empty?

    integer = Integer(string, exception: false)
    return integer if integer

    Float(string)
  rescue ArgumentError, TypeError
    raise ArgumentError, "数値ではありません: #{value.inspect}"
  end

  def cast_date(value)
    Date.iso8601(value.to_s)
  rescue ArgumentError, TypeError
    raise ArgumentError, "日付ではありません: #{value.inspect}"
  end

  def cast_date_range(value)
    hash = value || {}
    {
      "#{name}_start" => cast_date(hash["start"] || hash[:start]),
      "#{name}_end" => cast_date(hash["end"] || hash[:end])
    }
  end
end
