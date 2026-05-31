# ダッシュボード上の 1 ウィジェット（トピック12）。特定の `Query` の最新結果を
# 表示する。設定値（位置・列幅・タイトル上書き）のみを持ち、結果データ本体は
# `query_executions` 側が保持する。並べ替えは `position` カラム＋「上へ/下へ」
# （隣接ウィジェットとのスワップ。端は no-op）。
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

  # 直前（position が 1 つ小さい）のウィジェットと `position` を入れ替える。
  # 先頭（直前が無い）なら何もしない。
  def move_up!
    swap_with(previous_sibling)
  end

  # 直後（position が 1 つ大きい）のウィジェットと `position` を入れ替える。
  # 末尾（直後が無い）なら何もしない。
  def move_down!
    swap_with(next_sibling)
  end

  private

  def previous_sibling
    dashboard.widgets.where(position: ...position).order(position: :desc).first
  end

  def next_sibling
    dashboard.widgets.where("position > ?", position).order(:position).first
  end

  # 隣接ウィジェットと `position` を入れ替える。一意制約は張っていないため
  # 中間状態（一時的な position 重複）が起きても問題ない。
  def swap_with(other)
    return if other.nil?

    own_position = position
    transaction do
      update!(position: other.position)
      other.update!(position: own_position)
    end
  end
end
