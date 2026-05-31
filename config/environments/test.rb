# The test environment is used exclusively to run your application's
# test suite. You never need to work with it otherwise. Remember that
# your test database is "scratch space" for the test suite and is wiped
# and recreated between test runs. Don't rely on the data there!

Rails.application.configure do
  # Settings specified here will take precedence over those in config/application.rb.

  # While tests run files are not watched, reloading is not necessary.
  config.enable_reloading = false

  # Eager loading loads your entire application. When running a single test locally,
  # this is usually not necessary, and can slow down your test suite. However, it's
  # recommended that you enable it in continuous integration systems to ensure eager
  # loading is working properly before deploying your code.
  config.eager_load = ENV["CI"].present?

  # Configure public file server for tests with cache-control for performance.
  config.public_file_server.headers = { "cache-control" => "public, max-age=3600" }

  # CSV ダウンロード（トピック10）は X-Sendfile（本番は Thruster）で配信する。
  # テストでも send_file が X-Sendfile ヘッダーを立てるよう明示設定する。
  config.action_dispatch.x_sendfile_header = "X-Sendfile"

  # Show full error reports.
  config.consider_all_requests_local = true
  # スキーマキャッシュ（SolidCache 方式）の検証のため、テストでは memory_store を使う。
  # デフォルトの :null_store は書き込みが no-op で TTL/取得を検証できないため。
  config.cache_store = :memory_store

  # Render exception templates for rescuable exceptions and raise for other exceptions.
  config.action_dispatch.show_exceptions = :rescuable

  # Disable request forgery protection in test environment.
  config.action_controller.allow_forgery_protection = false

  # Active Record Encryption（Bigquery::Connection#service_account_json など）の鍵は
  # テストでは credentials（config/master.key で復号）に依存させず、固定のダミー値を使う。
  # CI では RAILS_MASTER_KEY を渡さないため、credentials を復号できず
  # "Missing Active Record encryption credential" で落ちるのを防ぐ。
  config.active_record.encryption.primary_key = "test_ar_encryption_primary_key"
  config.active_record.encryption.deterministic_key = "test_ar_encryption_deterministic_key"
  config.active_record.encryption.key_derivation_salt = "test_ar_encryption_key_derivation_salt"

  # Store uploaded files on the local file system in a temporary directory.
  config.active_storage.service = :test

  # Tell Action Mailer not to deliver emails to the real world.
  # The :test delivery method accumulates sent emails in the
  # ActionMailer::Base.deliveries array.
  config.action_mailer.delivery_method = :test

  # Set host to be used by links generated in mailer templates.
  config.action_mailer.default_url_options = { host: "example.com" }

  # Print deprecation notices to the stderr.
  config.active_support.deprecation = :stderr

  # Raises error for missing translations.
  # config.i18n.raise_on_missing_translations = true

  # Annotate rendered view with file names.
  # config.action_view.annotate_rendered_view_with_filenames = true

  # Raise error when a before_action's only/except options reference missing actions.
  config.action_controller.raise_on_missing_callback_actions = true
end
