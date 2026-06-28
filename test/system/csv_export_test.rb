require "application_system_test_case"

# rack_test（JSなし）。CSV ダウンロードリンクの存在と、リンク先が
# X-Sendfile で配信されることを確認する（実体配信は本番 Thruster）。
class CsvExportTest < ApplicationSystemTestCase
  setup do
    @user = create_user(role: "member", email: "member@example.com", password: "password")
    @connection = create_bigquery_connection(name: "本番接続")
    @query = create_query(user: @user, title: "結果クエリ", bigquery_connection: @connection)
  end

  def csv_dir
    Pathname.new(ENV.fetch("BEAMS_CSV_PATH") { Rails.root.join("storage/csv").to_s })
  end

  teardown do
    Dir.glob(csv_dir.join("*.csv.gz")).each { |f| File.delete(f) }
  end

  def log_in
    visit new_session_path
    fill_in "メールアドレス", with: "member@example.com"
    fill_in "パスワード", with: "password"
    click_button "ログイン"
  end

  def write_csv_for(execution)
    FileUtils.mkdir_p(csv_dir)
    Zlib::GzipWriter.open(csv_dir.join("#{execution.id}.csv.gz")) { |gz| gz.write("n\n1\n2\n") }
  end

  test "offers a CSV download link on a succeeded result and serves it" do
    execution = create_succeeded_query_execution(query: @query)
    execution.store_result([ { "name" => "n", "type" => "INTEGER" } ], [ [ 1 ], [ 2 ] ])
    execution.save!
    write_csv_for(execution)

    log_in
    visit query_path(@query)

    assert page.has_link?("CSVダウンロード", href: latest_csv_query_executions_path(@query))

    # リンク先（X-Sendfile 配信）が成功すること。
    page.driver.get latest_csv_query_executions_path(@query)
    assert_equal 200, page.driver.response.status
    assert_includes page.driver.response.headers["Content-Type"], "text/csv"
  end
end
