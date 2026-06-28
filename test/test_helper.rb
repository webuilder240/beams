ENV["RAILS_ENV"] ||= "test"
require_relative "../config/environment"
require "rails/test_help"
require "simplecov"

SimpleCov.start "rails" do
  # system テストだけ走らせた時にカバレッジ閾値で落ちないようにする運用は spec_helper と同じ。
  minimum_coverage 85 unless ENV["SKIP_COVERAGE_CHECK"]
  add_filter "/app/controllers/application_controller.rb"
  add_filter "/app/models/application_record.rb"
  add_filter "/app/jobs/application_job.rb"
  add_filter "/app/mailers/application_mailer.rb"
  add_filter "/app/helpers/application_helper.rb"
end

# test/support/ 配下のヘルパーを自動読み込み（spec/support と同等の挙動）
Rails.root.glob("test/support/**/*.rb").sort_by(&:to_s).each { |f| require f }

# minitest 6 では Object#stub が標準で提供されない（minitest 5 では mock.rb の中にあった）。
# gem 追加を避けるため、互換実装を test_helper 内に置く。第二引数はリテラル値か proc を受ける。
class Object
  def stub(method_name, value_or_proc)
    new_method = lambda do |*a, **k, &b|
      if value_or_proc.respond_to?(:call)
        value_or_proc.call(*a, **k, &b)
      else
        value_or_proc
      end
    end
    sc = singleton_class
    had_singleton = sc.public_method_defined?(method_name, false) || sc.private_method_defined?(method_name, false)
    original = sc.instance_method(method_name) if had_singleton
    define_singleton_method(method_name, &new_method)
    yield self
  ensure
    sc = singleton_class
    sc.send(:remove_method, method_name) if sc.method_defined?(method_name, false) || sc.private_method_defined?(method_name, false)
    sc.send(:define_method, method_name, original) if original
  end
end

module ActiveSupport
  class TestCase
    # gem 追加なし、Rails 標準の parallelize。SQLite では worker ごとに
    # test-<pid>.sqlite3 が用意されるためテスト DB が自動分離される。
    parallelize(workers: ENV.fetch("PARALLEL_WORKERS", :number_of_processors))

    # 並列実行 worker ごとに CSV 出力ディレクトリを分離する。
    # QueryExecutionJob / CsvExportsController は ENV["BEAMS_CSV_PATH"] を読むため
    # ここで worker ごとにユニークなパスを指す。
    parallelize_setup do |worker|
      ENV["BEAMS_CSV_PATH"] = Rails.root.join("tmp/test-csv-#{worker}").to_s
    end

    parallelize_teardown do |worker|
      FileUtils.rm_rf(Rails.root.join("tmp/test-csv-#{worker}"))
    end

    # fixture は使わず TestData ヘルパー（create_user 等）でレコードを都度作る方針。
    # 1 件きり共有が必要な setting だけ別途呼び出し側で create する。
    include TestData

    setup do
      Rails.cache.clear
    end
  end
end
