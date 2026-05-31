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
    # Turbo のリダイレクト完了を待つ（js: true では非同期。rack_test では即時）。
    expect(page).to have_content("ログアウト", wait: 10)
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

  # 名前クリックでクエリエディタへ挿入する `js: true` 結合テストはトピック07で実装した。
  # スキーマブラウザはクエリエディタ画面（/queries/new・/edit）に埋め込まれ、
  # カラム名クリックで `schema-browser:insert`（detail.name）を dispatch → エディタへ挿入する。
  # 実体の結合検証は spec/system/schema_browser_integration_spec.rb（js: true）で行う。
  # ここでは「クリックで `schema-browser:insert` イベントが document に発火する」ことを
  # エディタ非依存に確認する（06 のスコープ: イベント発火の担保）。
  it "dispatches schema-browser:insert on column click", js: true do
    log_in
    visit schema_browser_path

    received = page.evaluate_async_script(<<~JS)
      const done = arguments[0];
      document.addEventListener("schema-browser:insert", (e) => done(e.detail && e.detail.name), { once: true });
      const el = Array.from(document.querySelectorAll(".schema-browser__insertable"))
        .find((n) => n.textContent.trim() === "user_id");
      el.click();
    JS

    expect(received).to eq("user_id")
  end
end
