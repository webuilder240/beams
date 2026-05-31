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
end
