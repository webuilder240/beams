# 現在処理中のリクエスト/ジョブに紐づく属性を保持する。
# トピック23（Bugsnag）で `Current.user` を例外イベントに付与するために導入。
# ActiveSupport::CurrentAttributes はリクエスト終了時に Rails が自動でリセットするため、
# スレッド汚染の心配はない。
class Current < ActiveSupport::CurrentAttributes
  attribute :user
end
