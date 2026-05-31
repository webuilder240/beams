# 作業進捗ログ — トピック07: クエリエディタ（CodeMirror 6）

> タスク `docs/tasks/07-query-editor.md` の作業ログ（時系列）。司令塔・Coder・Tester のアクションを記録。

- **ステータス**: ✅完了
- **担当**: Coder / Tester

## 司令塔メモ（着手時の判断）

- **新規マイグレーション必要**: `queries` テーブル → マイグレーション承認ゲートに入る。
- **命名判断（司令塔）**:
  - `Query` モデルは **フラットなトップレベル**（ネームスペースなし）。ユーザーの保存クエリというコアドメイン概念であり、BigQuery インフラ固有ではないため。
  - 接続への FK は **`bigquery_connection_id`**（`references :bigquery_connection`、nullable）。アソシエーションは `belongs_to :bigquery_connection, class_name: "Bigquery::Connection", optional: true`。
  - `user_id` は FK・NOT NULL（`belongs_to :user`）。
- **環境確認**: Node 24 / npx / `capybara-playwright-driver` / chromium キャッシュあり → `js: true`（Playwright/chromium）実行可能。
- **06連携**: スキーマブラウザのカスタムイベントは確定済み **`schema-browser:insert`（`detail.name` に名前）**。07のエディタ側でこれを listen してカーソル挿入する。06でpendingにした js:true エディタ挿入テストは本トピックで実装・green 化する。
- **CodeMirror 6**: importmap CDN pin（00-overview Aで確定）。`@codemirror/*` + `@lezer/*` 依存を `bin/importmap pin` で列挙。

## 時系列ログ

### 2026-05-31

- **司令塔**: トピック06完了を受け、依存（04・06）充足済みのトピック07に着手。新規 Coder をアサイン。`queries` テーブルのマイグレーションが必要 → 承認ゲート。確認用ドキュメント作成を指示。
- **Coder→司令塔**: `queries` マイグレーション＋確認ドキュメント作成。論点3点（FK名 bigquery_connection_id / nullable / title index なし）を提起。司令塔: いずれも妥当。
- **司令塔→人間**: `queries` マイグレーション承認を依頼。
- **人間→司令塔**: 承認保留 → **`bigquery_connection_id` を NOT NULL（接続必須）に変更すること**。
- **司令塔（確定）**: `bigquery_connection_id` を `null: false` に変更（接続必須・下書きでも接続選択を要求）。アソシエーションは `belongs_to :bigquery_connection, class_name: "Bigquery::Connection"`（optional 撤回）。Factory は接続を生成。ボスが具体指定した修正＝改訂版マイグレーションの承認とみなし、修正適用後に migrate を許可。
- **司令塔→Coder**: マイグレーションを NOT NULL に修正＋確認doc更新 → migrate 実行 → トピック07 本実装（TDD）を指示。

### 2026-05-31（続き・Coder 本実装）

- **マイグレーション(A)**: `bigquery_connection_id` を `null: false` に修正、確認doc `07-queries-migration.md` を改訂版（接続必須）に更新。**承認済みとして `bin/rails db:migrate` + `db:test:prepare` 実行**。`db/schema.rb` を `version: 20260531100000` に更新（`queries` テーブル: title/sql_body/user_id(NOT NULL,FK)/bigquery_connection_id(NOT NULL,FK)/timestamps、index は user_id・bigquery_connection_id）。commit「queries マイグレーション(接続必須)」。
- **Query モデル + CRUD（TDD）**:
  - `spec/models/query_spec.rb`（red→green）。`app/models/query.rb`: `belongs_to :user` / `belongs_to :bigquery_connection, class_name: "Bigquery::Connection"`（接続必須）、`validates :title/:sql_body, presence: true`、`scope :title_matching`（`LIKE '%...%'`、`sanitize_sql_like`）。`User has_many :queries, dependent: :destroy`。
  - Factory `spec/factories/queries.rb`（user + bigquery_connection + sequence(:title)）。
  - `spec/requests/queries_spec.rb`（red→green）。`QueriesController`: `require_login`、**所有者スコープ `current_user.queries` 徹底**（他人の id は 404）、index は `updated_at desc` + `?q=` タイトル部分一致、strong params は `title/sql_body/bigquery_connection_id` のみ。`resources :queries` ルート。ビュー一式（index 検索フォーム/new/edit/show/_form/_errors）。commit「Query モデルとCRUD」。
- **CodeMirror 6 + Stimulus**:
  - `@codemirror/commands` を esm.sh CDN pin に追加（既存の CDN pin 方式に統一。jspm vendoring は破棄）。`bin/importmap audit` 0。
  - `app/javascript/controllers/query_editor_controller.js`: connect で `EditorView` を textarea にかぶせてマウント（`lineNumbers`/`history`/`highlightActiveLine`/`syntaxHighlighting(defaultHighlightStyle)`/`sql()`/`defaultKeymap`）、`dispatchTransactions` で隠し textarea にリアルタイム同期、disconnect で `destroy()`。
  - rack_test system spec `spec/system/queries_spec.rb`（一覧・新規・保存・削除・検索・接続0件誘導・Stimulus マウント確認）。
  - js:true system spec `spec/system/query_editor_js_spec.rb`（`.cm-editor`/`.cm-gutters` 出現・文字入力→保存で `sql_body` 保存・edit で既存SQL表示）。**login の Turbo リダイレクト完了待ち（`have_content("ログアウト")`）が js:true で必須**（無いと require_login で弾かれる race）。commit「CodeMirrorエディタ(importmap pin+Stimulus)」。
- **06 連携（名前挿入）**:
  - スキーマブラウザをクエリエディタ画面（new/edit）に埋め込み（`load_schema_for`: キャッシュ済み接続のみ、未キャッシュは同期せず非表示でコスト回避）。`_form` を 2 カラム化（エディタ + スキーマ aside）。
  - `query_editor_controller.js` が document の `schema-browser:insert`（`detail.name`）を listen → カーソル位置に挿入（イベント名は両コントローラのコメントに明記、06 と一致）。
  - 結合 system spec `spec/system/schema_browser_integration_spec.rb`（js:true、`cached_schema`/`Rails.cache.exist?` を stub、カラム名クリック→`.cm-content` に挿入）。
  - **06 の pending（`schema_browser_spec.rb` の js:true エディタ挿入）を green 化**: `schema-browser:insert` が document に発火することを `evaluate_async_script` で検証する実テストに置換。commit「スキーマブラウザ名前挿入連携」。
- **テスト間キャッシュ漏れ対策**: `spec/support/cache.rb` で各例前に `Rails.cache.clear`（memory_store のスキーマキャッシュが後続例に漏れる問題を解消）。
- **完了確認**: `bundle exec rspec` **161 examples / 0 failures / 0 pending**、SimpleCov **99.66%**（≥85%）。`bin/rubocop` 0 offenses、`bin/brakeman --no-pager` 0 warnings、`bin/bundler-audit` / `bin/importmap audit` クリーン。
- **設計判断メモ**:
  - 所有者スコープは `current_user.queries.find` で統一（他人のクエリは `RecordNotFound`→404。request spec は raise ではなく 404 レスポンスで検証）。
  - 接続必須(NOT NULL)に伴い、new フォームは接続 1 件ならデフォルト選択、0 件なら接続登録へ誘導（保存不可）。
  - エディタは textarea フォールバック方式（JS 無効でも編集可・rack_test で値検証可、js では非表示にして CM をかぶせる）。
  - `*Service` 不使用。ドメインロジック（`title_matching`）は Query モデルの scope に配置。
- **残課題（Tester/後続向け）**: クエリ実行・結果表示はトピック10へ委譲（本トピック対象外）。スキーマブラウザ埋め込みは「キャッシュ済み接続のみ表示」のため、未キャッシュ接続では new/edit で名前挿入 UI が出ない（運用上はスキーマブラウザ画面で先にキャッシュ。許容と判断）。
- **ステータス更新**: 🔄進行中 → ✅完了（Coder）。`00-overview.md` / `PROGRESS_LOG.md` の表も更新。
- **司令塔→Tester**: トピック07 の QA（js:true 実行確認を含む）を依頼。
- **Tester→司令塔**: トピック07 QA **PASS**。全受け入れ条件✅。接続必須(NOT NULL)をモデル/DB両層で実機確認。**js:true は `npx playwright install chromium` 後に Playwright/chromium で実起動・green（query_editor 3例 + schema連携 1例、skip/pendingなし）**。rspec 161例 0 failures 0 pending・カバレッジ99.66%、rubocop no offenses、brakeman 0、importmap audit クリーン。問題0件。差し戻し不要。
- **司令塔**: トピック07 を **✅完了** と確定。
