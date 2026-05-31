require "rails_helper"

# rack_test（JSなし）。CSV ダウンロードリンクの存在と、リンク先が
# X-Sendfile で配信されることを確認する（実体配信は本番 Thruster）。
RSpec.describe "CSV export", type: :system do
  let!(:user) { create(:user, :member, email: "member@example.com", password: "password") }
  let(:connection) { create(:bigquery_connection, name: "本番接続") }
  let(:query) { create(:query, user: user, title: "結果クエリ", bigquery_connection: connection) }

  def log_in
    visit new_session_path
    fill_in "メールアドレス", with: "member@example.com"
    fill_in "パスワード", with: "password"
    click_button "ログイン"
  end

  def write_csv_for(execution)
    dir = Rails.root.join("storage/csv")
    FileUtils.mkdir_p(dir)
    Zlib::GzipWriter.open(dir.join("#{execution.id}.csv.gz")) { |gz| gz.write("n\n1\n2\n") }
  end

  after { FileUtils.rm_rf(Rails.root.join("storage/csv")) }

  it "offers a CSV download link on a succeeded result and serves it" do
    execution = create(:query_execution, :succeeded, query: query)
    execution.store_result([ { "name" => "n", "type" => "INTEGER" } ], [ [ 1 ], [ 2 ] ])
    execution.save!
    write_csv_for(execution)

    log_in
    visit query_path(query)

    expect(page).to have_link("CSVダウンロード", href: latest_csv_query_executions_path(query))

    # リンク先（X-Sendfile 配信）が成功すること。
    page.driver.get latest_csv_query_executions_path(query)
    expect(page.driver.response.status).to eq(200)
    expect(page.driver.response.headers["Content-Type"]).to include("text/csv")
  end
end
