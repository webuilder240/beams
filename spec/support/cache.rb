# テスト間で memory_store のキャッシュが漏れないよう、各例の前にクリアする。
# （スキーマキャッシュ等が後続の例に影響しないようにする。）
RSpec.configure do |config|
  config.before(:each) { Rails.cache.clear }
end
