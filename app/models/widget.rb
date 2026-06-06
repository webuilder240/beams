# ダッシュボード上の 1 ウィジェット（トピック12）。特定の `Query` の最新結果を
# 表示する。設定値（位置・列幅・タイトル上書き）のみを持ち、結果データ本体は
# `query_executions` 側が保持する。並べ替えは `position` カラム＋D&D
# （SortableJS + Stimulus コントローラ + Dashboard#reorder_widgets!）。
class Widget < ApplicationRecord
  COLUMN_SPANS = [ 1, 2 ].freeze

  belongs_to :dashboard
  belongs_to :query

  validates :position, numericality: { only_integer: true, greater_than_or_equal_to: 0 }
  validates :column_span, inclusion: { in: COLUMN_SPANS }

  # 表示タイトル。`title_override` が空なら `Query#title` を使う。
  def display_title
    title_override.presence || query.title
  end
end
