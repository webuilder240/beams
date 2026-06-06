# ダッシュボード（トピック12）。複数クエリの可視化（`Widget`）を縦積み/1〜2カラム
# グリッドにまとめる。`user` は所有者の記録のみで、閲覧/編集制限には使わない
# （計画書 §4.9: ログインユーザーは全ダッシュボードを閲覧・編集可）。
class Dashboard < ApplicationRecord
  belongs_to :user
  has_many :widgets, dependent: :destroy

  validates :title, presence: true, length: { maximum: 255 }

  # タイトル部分一致検索（§4.11）。空クエリは全件を返す。`Query.text_matching` と同方針
  # （ただしダッシュボードはタイトルのみ検索 — トピック21 B3-A）。
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
  # 呼び出し元（WidgetOrdersController#update / sortable_controller.js）は、
  # グリッド上の全ウィジェット ID を「並び替え後の順序」で送ってくる前提。
  # 部分配列でも動作するが、その場合は配列に含まれた ID のみが 0,1,2… に
  # 振り直され、含まれない ID の position はそのまま残る。
  #
  # Widget.update(ids, attrs) で ID ごとに UPDATE を発行する（Brakeman 安全）。
  # ウィジェット数は実運用で少数のため複数 UPDATE でも問題ない。
  def reorder_widgets!(ordered_ids)
    own_ids = widgets.pluck(:id)
    filtered = Array(ordered_ids).map(&:to_i).select { |id| own_ids.include?(id) }
    return if filtered.empty?

    attrs = filtered.each_with_index.map { |_id, index| { position: index } }

    transaction do
      Widget.update(filtered, attrs)
    end
  end
end
