require "test_helper"

# Capybara の Puma サーバを単一スレッドに固定（SQLite "database is locked" 対策）。
# spec/support/playwright.rb で行っていた設定を踏襲。
Capybara.register_server(:beams_puma) do |app, port, host|
  require "rack/handler/puma"
  Rack::Handler::Puma.run(app, Host: host, Port: port, Threads: "1:1", Silent: true)
end
Capybara.server = :beams_puma

# js を使う system test 用に Playwright ドライバを登録。
require "capybara/playwright"
Capybara.register_driver(:playwright) do |app|
  Capybara::Playwright::Driver.new(app, browser_type: :chromium, headless: true)
end

# JS なしの軽量 system test（rack_test）— 既定の基底クラス。
class ApplicationSystemTestCase < ActionDispatch::SystemTestCase
  driven_by :rack_test
end

# JS が必要な system test 用の基底クラス（Playwright/Chromium）。
class ApplicationJsSystemTestCase < ActionDispatch::SystemTestCase
  driven_by :playwright
end
