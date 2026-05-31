# トピック07: クエリエディタ（CodeMirror 6）

> CodeMirror 6をimportmapでピン留めし、SQLハイライト・行番号付きエディタとQueryモデルのCRUDを実装する。計画書 §4.3（前半）に対応。

- **ステータス**: 完了
- **依存**: [[04-bigquery-connection]]（ConnectionモデルのFKとしてQueryが参照する可能性がある）／[[06-schema-browser]]（スキーマブラウザからの名前挿入イベントを受信するため、Stimulusコントローラが先に存在していると結合しやすい）
- **関連計画書**: §4.3, §3（技術スタック表）

## ゴール（完了の定義）

- CodeMirror 6がimportmap（Node不使用）で読み込まれ、SQLハイライトと行番号が表示される
- `Query` モデル（タイトル・SQL本文・所有者）のCRUD（新規作成・保存・読み込み・一覧・削除）が動作する
- StimulusコントローラでエディタがDOMにマウントされ、フォームと双方向バインドされる
- [[06-schema-browser]] からのカスタムイベントを受けてエディタのカーソル位置に名前が挿入される
- クエリの実行・結果表示は [[10-query-execution]] に委譲する（このトピックには含めない）
- RSpecモデルスペック・リクエストスペック・System Specのカバレッジが85%以上を維持する

## 前提・参照

- Rails 8.1 / importmap（`config/importmap.rb`）。`bin/importmap pin` またはvendoredで取り込む
- Hotwire（Turbo / Stimulus）が既に動作している前提
- `app/javascript/controllers/` にStimulusコントローラを配置
- SQLエディタはCodeMirror 6（`@codemirror/view`, `@codemirror/state`, `@codemirror/lang-sql` 等）
- [[06-schema-browser]] が発火するカスタムイベント名は両トピック間で合わせて決定する（未決事項参照）

## タスク

### 1. CodeMirror 6のimportmap組み込み（CDN pinで実装）

- [x] `bin/importmap pin` でCM6の必要パッケージをCDN経由でピン留め（`config/importmap.rb`）— `@codemirror/state`, `@codemirror/view`, `@codemirror/commands`, `@codemirror/lang-sql` および必要な `@lezer/*` 依存を列挙してpin
  - 受け入れ条件: `config/importmap.rb` にCM6関連pinが追加され、ブラウザでエディタが初期化されSQLハイライト・行番号が表示される（System Spec `js: true` またはブラウザ手動確認）
- [x] `@lezer/*` 等の推移的依存が漏れていないことを確認し、ブラウザコンソールにimport解決エラーが出ないことを検証
  - 受け入れ条件: System Spec（`js: true`）でCM6エディタDOM（`.cm-editor`）が出現し、コンソールエラーなし

### 2. Queryモデル

- [x] `Query` モデル・マイグレーション作成（`app/models/query.rb`, `db/migrate/YYYYMMDDHHMMSS_create_queries.rb`）— `title`（string, NOT NULL）, `sql_body`（text, NOT NULL）, `user_id`（integer FK, NOT NULL）, `connection_id`（integer FK, nullable）を持つ
  - 受け入れ条件: `bin/rails db:migrate` が通り、`Query.create!(title: "t", sql_body: "SELECT 1", user_id: 1)` でレコードが保存できる
- [x] バリデーション追加（`app/models/query.rb`）— `title` presence, `sql_body` presence
  - 受け入れ条件: バリデーション失敗時に `query.errors` が適切なメッセージを返すことをRSpecで確認
- [x] `User` との `belongs_to` アソシエーション、`Connection` との `belongs_to :connection, optional: true`
  - 受け入れ条件: アソシエーションの確認をRSpecモデルスペックに含める
- [x] FactoryBot定義（`spec/factories/queries.rb`）— `user` と `sequence(:title)` を含む
  - 受け入れ条件: `create(:query)` でRSpecからレコードが作成できる
- [x] モデルスペック（`spec/models/query_spec.rb`）— バリデーション・アソシエーションを検証
  - 受け入れ条件: `bundle exec rspec spec/models/query_spec.rb` が全グリーン

### 3. QueriesコントローラとCRUD

- [x] `QueriesController` 作成（`app/controllers/queries_controller.rb`）— `index`, `new`, `create`, `edit`, `update`, `destroy`, `show` を実装
  - 受け入れ条件: リクエストスペック（`spec/requests/queries_spec.rb`）でindex/new/create/edit/update/destroyの各レスポンスコードが正しいことを確認
- [x] Strong Parameters（`query_params`）— `title`, `sql_body`, `connection_id` のみ許可
  - 受け入れ条件: 不正パラメータが無視されることをリクエストスペックで確認
- [x] `index` アクションは更新日時降順でクエリ一覧を返す、タイトル部分一致検索パラメータ対応（`params[:q]`）（§4.11）
  - 受け入れ条件: `?q=foo` でタイトルに "foo" を含む結果のみ返ることをリクエストスペックで確認
- [x] ルーティング追加（`config/routes.rb`）— `resources :queries`
  - 受け入れ条件: `bin/rails routes | grep queries` でRESTfulルートが確認できる

### 4. クエリエディタビュー

- [x] `app/views/queries/new.html.erb` / `edit.html.erb` / `show.html.erb` 作成 — `data-controller="query-editor"` を持つ `<div>` にCodeMirrorをマウントする領域、隠しフォームフィールド（`sql_body`）を含む
  - 受け入れ条件: rack_test System Spec（`spec/system/queries_spec.rb`）でページが200を返しフォームが存在することを確認
- [x] `app/views/queries/index.html.erb` 作成 — クエリ一覧表示、タイトル検索フォーム、新規作成リンク
  - 受け入れ条件: rack_test System Specでクエリ一覧が表示されることを確認
- [x] パーシャル `app/views/queries/_form.html.erb` 作成 — new/edit共通フォーム
  - 受け入れ条件: new・editページ両方でフォームが表示されることをrack_test System Specで確認

### 5. StimulusコントローラでのCodeMirror初期化

- [x] `app/javascript/controllers/query_editor_controller.js` 作成 — `connect()` でCodeMirror EditorViewを初期化、SQLハイライト・行番号・basicSetupを設定、初期値として隠しフィールドの値をセット
  - 受け入れ条件: System Spec（`js: true`、`spec/system/queries_spec.rb`）でCM6エディタのDOMクラス（`.cm-editor` 等）が存在することを確認
- [x] エディタ内容変更時に隠しフォームフィールド（`sql_body`）をリアルタイム同期するTransactionの `dispatchTransaction` 設定（`app/javascript/controllers/query_editor_controller.js`）
  - 受け入れ条件: System Spec（`js: true`）でエディタに文字入力後にフォーム送信すると `sql_body` が保存されることを確認
- [x] `disconnect()` でEditorViewを `destroy()` して後始末
  - 受け入れ条件: メモリリークしないこと（手動確認または System Spec のページ遷移後エラーなし）

### 6. スキーマブラウザからの名前挿入連携

- [x] [[06-schema-browser]] が発火するカスタムイベント（例: `schema-browser:insert`、`detail.name` に名前）をlistenするイベントハンドラを `query_editor_controller.js` に追加
  - 受け入れ条件: System Spec（`js: true`、`spec/system/schema_browser_integration_spec.rb`）でスキーマツリーのカラム名クリック後にエディタに名前が挿入されることを確認
- [x] イベント名・detail構造を `app/javascript/controllers/query_editor_controller.js` のコメントまたは `docs/` に記録し、[[06-schema-browser]] 側と合わせる
  - 受け入れ条件: 両コントローラのコメントかドキュメントにイベント名が明記されている

### 7. 保存・読み込みUX

- [x] 保存ボタン（`app/views/queries/_form.html.erb`）— Turbo対応フォームで保存後にクエリeditorページにリダイレクト
  - 受け入れ条件: System Spec（rack_test）で保存後に `show` or `edit` へリダイレクトされることを確認
- [x] 既存クエリの読み込み（`edit` アクション）— エディタに保存済み `sql_body` が初期値としてセットされる
  - 受け入れ条件: System Spec（`js: true`）で既存クエリのeditページを開くとエディタに既存SQL文字列が表示されることを確認
- [x] 削除リンク（`app/views/queries/index.html.erb` or `show.html.erb`）— Turbo Confirmダイアログ付き
  - 受け入れ条件: rack_test System Specで削除後にindexへリダイレクトされることを確認

### 8. RSpec・カバレッジ

- [x] `bundle exec rspec spec/models/query_spec.rb spec/requests/queries_spec.rb spec/system/queries_spec.rb` が全グリーン
  - 受け入れ条件: SimpleCov 85%以上（CIと同条件）
- [x] `bundle exec rspec spec/system/schema_browser_integration_spec.rb` が全グリーン（[[06-schema-browser]] との結合、`js: true`）
  - 受け入れ条件: エディタへの挿入が確認でき、グリーンになる

## 動作確認

- [x] `bin/rails db:migrate db:test:prepare` が通る
- [x] rack_test System Spec でクエリ一覧・新規作成・保存・削除の基本フローが確認できる（`spec/system/queries_spec.rb`）
- [x] `js: true` System Spec でCodeMirrorエディタが表示され（`.cm-editor` DOM）、文字入力が可能であることを確認
- [x] `js: true` System Spec でスキーマブラウザからの名前挿入がエディタに反映されることを確認（BigQueryをstub）
- [x] `bin/rubocop app/controllers/queries_controller.rb app/models/query.rb app/javascript/controllers/query_editor_controller.js` が警告なし（JSはRuboCop対象外のため手動確認）

## 未決事項・質問

- ✅決定: CDN pinで確定（2026-05-31）。`bin/importmap pin` で依存を列挙。依存漏れに注意し、将来オフライン要件が出たらvendoringへ移行余地あり。
- `Query` モデルに `connection_id` を持たせるかどうかは [[04-bigquery-connection]] の `Connection` モデル設計確定後に決定。初期は optional とする。
- スキーマブラウザとの挿入連携のカスタムイベント名（`detail` の構造を含む）は [[06-schema-browser]] 担当と合わせて確定する。
- `Playwright` + `js: true` のSystem Specを初回実行する前に `npx playwright install chromium` が必要（CLAUDE.md参照）。CI環境でのインストール手順を確認すること。
