# クエリ結果（`QueryExecution#result` の `{schema:, rows:}`）を Chart.js で描画する
# ための設定を保持する（トピック11）。`Query has_one :visualization`（1クエリ1可視化）。
# 結果データ本体は持たず、軸・系列・チャート種別・表示モード・counter 設定のみを保存する。
class Visualization < ApplicationRecord
  CHART_TYPES = %w[line bar pie area scatter counter].freeze
  DISPLAY_MODES = %w[table chart].freeze
  AGGREGATIONS = %w[sum avg count min max].freeze

  belongs_to :query

  # Y 軸カラム名の配列（複数 Y 軸）を JSON 文字列で `y_columns`(text) に保存する。
  serialize :y_columns, coder: JSON

  validates :chart_type, inclusion: { in: CHART_TYPES }
  validates :display_mode, inclusion: { in: DISPLAY_MODES }
  validates :counter_aggregation, inclusion: { in: AGGREGATIONS }
  validates :query_id, uniqueness: true

  # counter（カウンター）表示の単一集計値を返す。**BigQuery に再クエリせず**、
  # 取得済み結果（`execution.result` の `rows`/`schema`）に対しアプリ層で集計する。
  # 集計対象は `counter_column`、集計方法は `counter_aggregation`（sum/avg/count/min/max）。
  # - count は対象カラムの「非 NULL 件数」（司令塔決定）。
  # - sum は数値以外を 0 として扱う安全側。avg/min/max は数値が 1 件もなければ nil。
  # 列未設定・列がスキーマに無い・結果未保存の場合は nil。
  def counter_value(execution)
    return nil if counter_column.blank?

    result = execution&.result
    return nil if result.nil?

    index = column_index(result[:schema])
    return nil if index.nil?

    values = result[:rows].map { |row| row[index] }
    aggregate(values)
  end

  private

  def column_index(schema)
    Array(schema).index { |col| col["name"] == counter_column }
  end

  def aggregate(values)
    case counter_aggregation
    when "count" then values.count { |v| !v.nil? }
    when "sum"   then numeric(values).sum(0)
    when "avg"   then average(numeric(values))
    when "min"   then numeric(values).min
    when "max"   then numeric(values).max
    end
  end

  def numeric(values)
    values.filter_map { |v| Float(v) rescue nil }
  end

  def average(nums)
    return nil if nums.empty?

    nums.sum / nums.size
  end
end
