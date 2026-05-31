Capybara.register_driver(:playwright) do |app|
  Capybara::Playwright::Driver.new(app,
    browser_type: :chromium,
    headless: true
  )
end

# js: true（Playwright）の System Spec では Capybara が Puma アプリサーバを起動し、
# ブラウザからの HTTP リクエストを別スレッドで処理する。Capybara 既定の Puma は
# マルチスレッド（0:4）で、各スレッドが SQLite への独立コネクションを掴むため、
# use_transactional_fixtures のテスト用トランザクションとデッドロックして
# "SQLite3::BusyException: database is locked" を引き起こす。
# サーバを単一スレッドに固定し、テストスレッドのコネクションと競合させない。
Capybara.register_server(:beams_puma) do |app, port, host|
  require "rack/handler/puma"
  Rack::Handler::Puma.run(app, Host: host, Port: port, Threads: "1:1", Silent: true)
end
Capybara.server = :beams_puma

RSpec.configure do |config|
  config.before(:each, type: :system) do |example|
    if example.metadata[:js]
      driven_by :playwright
    else
      driven_by :rack_test
    end
  end
end
