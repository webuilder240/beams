require "rails_helper"

RSpec.describe "Schema browser", type: :system do
  let!(:user) { create(:user, :member, email: "member@example.com", password: "password") }
  let!(:connection) { create(:bigquery_connection) }

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
                { column_name: "user_id", data_type: "STRING",
                  is_nullable: true, ordinal_position: 1 },
                { column_name: "amount", data_type: "INT64",
                  is_nullable: false, ordinal_position: 2 }
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
  end

  before do
    allow_any_instance_of(Bigquery::Connection)
      .to receive(:cached_schema).and_return(schema_structure)
  end

  it "renders the dataset/table/column tree (rack_test)" do
    log_in
    visit schema_browser_path

    expect(page).to have_content("analytics")
    expect(page).to have_content("events")
    expect(page).to have_content("user_id")
    expect(page).to have_content("amount")
    # data-controller 属性が付与されている（Stimulus 配線）
    expect(page).to have_css("[data-controller='schema-browser']")
    # 手動更新ボタンが存在する
    expect(page).to have_button("スキーマを更新")
  end

  # 名前クリックでクエリエディタへ挿入する `js: true` テストはトピック07に委ねる。
  # 本トピックでは Stimulus の `schema-browser:insert` イベント発火/クリップボード
  # コピーまでがスコープであり、エディタ側リスナの配線は07で行うため。
  # （加えて、この環境では playwright/chromium の利用可否が未確認のため、ここでは pending とする。）
  it "inserts a name into the editor on click", js: true do
    pending("エディタ配線はトピック07。js:true(playwright/chromium)は07で検証する。")
    raise "not implemented in this topic"
  end
end
