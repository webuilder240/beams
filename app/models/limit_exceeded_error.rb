# dry-run のスキャン量が接続の `maximum_bytes_billed` を超えたときに使う例外。
# コントローラが `rescue LimitExceededError` できるよう `app/models/` 配下に定義する
# （`*Service` 禁止方針に沿ったドメイン例外の置き場）。
class LimitExceededError < StandardError
end
