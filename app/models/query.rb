class Query < ApplicationRecord
  # `{{ name }}` / `{{ name:type }}` 記法を取り出す正規表現。
  # name は識別子（英数字とアンダースコア、先頭は非数字）に限定する。
  PARAMETER_PATTERN = /\{\{\s*([a-zA-Z_]\w*)\s*(?::\s*(\w+)\s*)?\}\}/

  belongs_to :user
  belongs_to :bigquery_connection, class_name: "Bigquery::Connection"

  has_many :query_parameters, -> { order(:id) }, dependent: :destroy
  has_many :query_executions, dependent: :destroy
  has_one :visualization, dependent: :destroy

  validates :title, presence: true
  validates :sql_body, presence: true

  after_save :sync_parameters!

  # 最新の成功実行（succeeded）を 1 件返す。結果は上書き運用のため通常 1 件だが、
  # 念のため作成日時の降順で最新を選ぶ。`(query_id, status)` 複合 index が効く。
  def latest_succeeded_execution
    query_executions.where(status: :succeeded).order(created_at: :desc).first
  end

  # タイトル部分一致検索（§4.11）。空クエリは全件を返す。
  # SQLite は `\` を既定のエスケープ文字として扱わないため、`sanitize_sql_like`
  # が生成する `\` を有効化する `ESCAPE '\'` を明示する（`%` `_` を文字どおり扱う）。
  scope :title_matching, ->(term) {
    next all if term.blank?

    where("title LIKE ? ESCAPE '\\'", "%#{sanitize_sql_like(term)}%")
  }

  # SQL 本文から `{{ name }}` パラメータをパースし、`[{ name:, type: }]` の配列を返す。
  # - 同名は最初の出現（型）に正規化して 1 件にまとめる（出現順を維持）。
  # - 不明な型注釈（例: `{{ x:unknown }}`）は `:string` にフォールバックする。
  def parameters
    return [] if sql_body.blank?

    sql_body.scan(PARAMETER_PATTERN).each_with_object([]) do |(name, type), acc|
      next if acc.any? { |p| p[:name] == name }

      acc << { name: name, type: normalize_type(type) }
    end
  end

  # SQL 保存時にパース結果で `query_parameters` を同期する（追加・更新・削除）。
  # `(query_id, name)` をキーに upsert し、SQL から消えたパラメータは削除する。
  def sync_parameters!
    parsed = parameters
    keep_names = parsed.map { |p| p[:name] }

    if keep_names.empty?
      query_parameters.destroy_all
    else
      query_parameters.where.not(name: keep_names).destroy_all
    end

    parsed.each do |p|
      record = query_parameters.find_or_initialize_by(name: p[:name])
      record.update!(param_type: p[:type].to_s)
    end

    query_parameters.reset
  end

  # SQL 内の `{{ name }}` / `{{ name:type }}` を BigQuery バインド名 `@name` に
  # 置換した SQL を返す。**文字列連結は一切行わない**（値はバインド側で渡す）。
  def bound_sql
    return sql_body if sql_body.blank?

    sql_body.gsub(PARAMETER_PATTERN) { "@#{Regexp.last_match(1)}" }
  end

  # 実行時の生入力（`{ name => value }`）を、定義済みパラメータ名のみに
  # ホワイトリストフィルタして返す。未定義の名前は無視する。
  def permit_parameter_values(raw)
    allowed = query_parameters.pluck(:name)
    (raw || {}).to_h.stringify_keys.slice(*allowed)
  end

  # 全パラメータ必須運用。値が空（blank）のパラメータ名の一覧を返す。
  # 1 つでも空があればこの配列が非空になり、実行を拒否できる。
  def missing_parameter_values(raw)
    permitted = permit_parameter_values(raw)
    query_parameters.select do |param|
      blank_value?(permitted[param.name], param.param_type)
    end.map(&:name)
  end

  private

  def blank_value?(value, param_type)
    if param_type == "date_range"
      hash = (value || {}).to_h.stringify_keys
      hash["start"].blank? || hash["end"].blank?
    else
      value.blank?
    end
  end

  def normalize_type(type)
    symbol = type.to_s.to_sym
    QueryParameter::SUPPORTED_TYPES.include?(symbol) ? symbol : :string
  end
end
