require "rails_helper"

# 06（スキーマブラウザ）× 07（クエリエディタ）の結合テスト。
# スキーマツリーのカラム名クリックで `schema-browser:insert`（detail.name）が
# document に dispatch され、query-editor コントローラがエディタへ名前を挿入する。
RSpec.describe "Schema browser → editor insertion (js)", type: :system, js: true do
  let!(:user) { create(:user, :member, email: "member@example.com", password: "password") }
  let!(:connection) { create(:bigquery_connection, name: "本番接続") }

  let(:schema_structure) do
    {
      fetched_at: Time.current,
      datasets: [
        {
          dataset_id: "analytics",
          name: "Analytics",
          tables: [
            {
              table_id: "events",
              table_type: "TABLE",
              columns: [
                { column_name: "user_id", data_type: "STRING", is_nullable: true, ordinal_position: 1 }
              ]
            }
          ]
        }
      ]
    }
  end

  def log_in
    visit new_session_path
    fill_in "メールアドレス", with: "member@example.com"
    fill_in "パスワード", with: "password"
    click_button "ログイン"
    expect(page).to have_content("ログアウト", wait: 10)
  end

  before do
    # スキーマブラウザがキャッシュ済みとみなし、BigQuery 実 API を呼ばない。
    allow(Rails.cache).to receive(:exist?).and_call_original
    allow(Rails.cache).to receive(:exist?)
      .with("bigquery:schema:#{connection.id}").and_return(true)
    allow_any_instance_of(Bigquery::Connection)
      .to receive(:cached_schema).and_return(schema_structure)
  end

  it "inserts a column name into the editor when clicked in the schema tree" do
    log_in
    visit new_query_path

    expect(page).to have_css(".cm-editor", wait: 10)
    expect(page).to have_css("[data-controller='schema-browser']", wait: 10)

    # データセット → テーブルを展開してカラムを表示する。
    find("button", text: "Analytics").click
    find("button", text: "events").click

    # カラム名「user_id」の挿入トリガをクリックする。
    within(".schema-browser") do
      find(".schema-browser__insertable", text: "user_id").click
    end

    # エディタに user_id が挿入される。
    expect(page).to have_css(".cm-content", text: "user_id", wait: 10)
  end
end
