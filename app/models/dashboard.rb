# ダッシュボード（トピック12）。複数クエリの可視化（`Widget`）を縦積み/1〜2カラム
# グリッドにまとめる。`user` は所有者の記録のみで、閲覧/編集制限には使わない
# （計画書 §4.9: ログインユーザーは全ダッシュボードを閲覧・編集可）。
class Dashboard < ApplicationRecord
  belongs_to :user
  has_many :widgets, dependent: :destroy

  validates :title, presence: true, length: { maximum: 255 }

  # タイトル部分一致検索（§4.11）。空クエリは全件を返す。`Query.title_matching` と同方針。
  # SQLite は `\` を既定のエスケープ文字として扱わないため、`ESCAPE '\'` を明示して
  # `sanitize_sql_like` が生成する `\` を有効化し、`%` `_` を文字どおり扱う。
  scope :title_matching, ->(term) {
    next all if term.blank?

    where("title LIKE ? ESCAPE '\\'", "%#{sanitize_sql_like(term)}%")
  }

  # `position` 昇順のウィジェット。show 画面の表示・並べ替えに使う。
  def ordered_widgets
    widgets.order(:position)
  end

  # D&D で確定した順序で position を一括更新する（トピック19）。
  # ordered_ids に含まれるこのダッシュボード所属の ID のみを対象とし、
  # 他ダッシュボードの ID や存在しない ID は無視する。
  # position は 0 始まりの連番で付け直す。トランザクションで実行。
  #
  # 呼び出し元（WidgetsController#reorder / sortable_controller.js）は、
  # グリッド上の全ウィジェット ID を「並び替え後の順序」で送ってくる前提。
  # 部分配列でも動作するが、その場合は配列に含まれた ID のみが 0,1,2… に
  # 振り直され、含まれない ID の position はそのまま残る。
  #
  # SQL は CASE 式を用いた単一 UPDATE で発行する（N+1 回避）。SQLite で動作。
  def reorder_widgets!(ordered_ids)
    own_ids = widgets.pluck(:id)
    filtered = Array(ordered_ids).map(&:to_i).select { |id| own_ids.include?(id) }
    return if filtered.empty?

    # CASE WHEN id = ? THEN ? ... END で各 ID の新 position を一括指定する。
    when_clauses = filtered.each_index.map { "WHEN id = ? THEN ?" }.join(" ")
    case_args = filtered.each_with_index.flat_map { |id, index| [ id, index ] }
    case_sql = "CASE #{when_clauses} END"

    transaction do
      widgets.where(id: filtered)
             .update_all([ "position = #{case_sql}", *case_args ])
    end
  end
end
