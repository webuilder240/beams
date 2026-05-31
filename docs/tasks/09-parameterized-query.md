# トピック09: パラメータ化クエリ

> `{{ name }}` 記法でSQLにパラメータを埋め込み、BigQueryネイティブバインド（`@param`）で安全に実行する。計画書 §4.5 に対応。

- **ステータス**: 完了
- **依存**: [[07-query-editor]]（`Query`モデル・クエリエディタビュー）／[[04-bigquery-connection]]（BigQueryクライアントラッパー）
- **関連計画書**: §4.5

## ゴール（完了の定義）
- `{{ name }}` 記法をパースしてパラメータ一覧を抽出できる
- 型4種（文字列 / 数値 / 日付 / 日付範囲）を定義・保存できる
- 実行時に入力フォームが自動表示される
- 値は必ずBigQueryネイティブパラメータ（`@param`）としてバインドされ、文字列連結は行われない
- SQLインジェクションが構造的に排除されている（`@param` バインドのみ許可）
- RSpecでパース・バインド・実行フローをカバー

## 前提・参照
- [[07-query-editor]] で `Query` モデルが実装済みであること（`Query#sql` カラムが存在する）
- [[04-bigquery-connection]] のBigQueryクライアントラッパーが `query_parameters:` オプションを受け取れること
- BigQuery Ruby SDK: `Google::Cloud::Bigquery::QueryParameter` を使ってパラメータをバインドする
- `{{ name }}` → `@name` 変換後のSQLをBigQueryに投げ、`query_parameters:` に型付きパラメータを渡す
- 動的ドロップダウン（クエリベース）は §5 非スコープ。実装しない

## タスク

### グループ1: パラメータパーサー（TDD）
- [x] `spec/models/query_parameter_spec.rb` にパース機能のテストを先に書く（失敗するRSpecを先に用意する）
  - 受け入れ条件: `Query#parameters` が `[{ name: "user_id", type: :number }]` を返すテストが **red** で存在する
- [x] `Query#parameters` インスタンスメソッドを `app/models/query.rb` に実装する — `{{ name }}`, `{{ name:number }}`, `{{ name:date }}`, `{{ name:date_range }}` 記法をパースし、`[{ name: String, type: Symbol }]` の配列を返す
  - 受け入れ条件: `query.parameters` が `[{ name: "user_id", type: :number }]` を返すテストが通る
- [x] 型の対応表を定数として `Query` または `QueryParameter` に定義する (`SUPPORTED_TYPES = %i[string number date date_range]`)
  - 受け入れ条件: 不明な型記法（例: `{{ x:unknown }}`）は `:string` にフォールバックするか、パースエラーとして返すかをテストで明確にする
- [x] `spec/models/query_parameter_spec.rb` を完成させる（`spec/models/` 以下に配置）
  - 受け入れ条件: パラメータなし・1個・複数・型4種・同名重複・不正記法のケースをカバーし、テストが **green** になるまで完了にしない

### グループ2: パラメータ定義の保存モデル
- [x] `query_parameters` テーブルを作成するマイグレーション (`db/migrate/YYYYMMDDHHMMSS_create_query_parameters.rb`) を作成する — カラム: `query_id:references`, `name:string`, `param_type:string`, `position:integer`
  - 受け入れ条件: `bin/rails db:migrate` が通る
- [x] `app/models/query_parameter.rb` を作成する — `belongs_to :query`, バリデーション（`name` 必須・英数字アンダースコアのみ, `param_type` が4種内）
  - 受け入れ条件: 不正な `name`（スペース含む等）・不正な `param_type` でバリデーションエラーになるモデルテストが通る
- [x] `app/models/query.rb` に `has_many :query_parameters, dependent: :destroy` と、SQL保存時にパラメータを自動同期するメソッド（`sync_parameters!`）を追加する
  - 受け入れ条件: `query.update(sql: "SELECT {{ x }}")` 後に `query.query_parameters.pluck(:name)` が `["x"]` になるテストが通る
- [x] `spec/models/query_parameter_spec.rb` を作成する
  - 受け入れ条件: バリデーション・関連のテストをカバー
- [x] `spec/models/query_spec.rb` に `sync_parameters!` のテストを追加する
  - 受け入れ条件: SQL変更でパラメータが追加・削除・更新される3ケースをカバー

### グループ3: `{{ name }}` → `@name` SQL変換とパラメータバインダー（TDD）
- [x] `spec/models/query_spec.rb` に `Query#bound_sql` のテストを先に書く（失敗するRSpecを先に用意する）
  - 受け入れ条件: `query.bound_sql` が `"SELECT @user_id"` を返すテストが **red** で存在する。文字列連結パスが存在しないことをテストで担保する
- [x] `Query#bound_sql` インスタンスメソッドを `app/models/query.rb` に実装する — SQL内の `{{ name }}` を `@name` に置換し、変換後SQLを返す
  - 受け入れ条件: `query.bound_sql` が `"SELECT @user_id"` を返すテストが通る
- [x] `spec/models/query_parameter_spec.rb` に `QueryParameter#to_bigquery_param` のテストを先に書く（失敗するRSpecを先に用意する）
  - 受け入れ条件: 型4種それぞれのバインドオブジェクト生成テストが **red** で存在する
- [x] `QueryParameter#to_bigquery_param` インスタンスメソッドを `app/models/query_parameter.rb` に実装する — `{ name, type, value }` から `Google::Cloud::Bigquery::QueryParameter` を生成する
  - 型マッピング: `string` → `STRING`, `number` → `FLOAT64`（または`INT64`、値が整数か判定）, `date` → `DATE`, `date_range` → 開始・終了を2つの `DATE` パラメータに展開
  - 受け入れ条件: 型4種・不正値（数値フィールドに文字列を渡す等）のテストが **green** になるまで完了にしない（`spec/models/` 以下に配置）

### グループ4: 実行時フォームUI
- [x] `app/views/queries/_parameter_form.html.erb` パーシャルを作成する — `query.query_parameters` を元に型別フォームフィールドを動的レンダリングする
  - `string`: `<input type="text">`
  - `number`: `<input type="number">`
  - `date`: `<input type="date">`
  - `date_range`: `<input type="date">` × 2（開始・終了）
  - 受け入れ条件: パラメータを持つQueryの実行画面でフォームが表示される
- [x] クエリ実行フォーム（`app/views/queries/show.html.erb` 相当）にパラメータフォームを組み込む
  - 受け入れ条件: パラメータなしのQueryではフォームが表示されない。パラメータありのQueryでは必須フィールドが空のまま送信できない（HTML5 `required`）
- [x] SQLエディタのSQL変更時にTurbo Frame（またはStimulusコントローラ）でパラメータフォームを再描画する仕組みを実装する (`app/javascript/controllers/parameter_form_controller.js`)
  - 受け入れ条件: SQL内の `{{ foo }}` を追加・削除するとフォームフィールドが動的に増減する（System Specで確認）

### グループ5: コントローラへのパラメータ受け渡し
- [x] `app/controllers/queries/executions_controller.rb`（[[10-query-execution]] で作成予定）のパラメータ受け取りロジックを設計する — `params[:query_params]` をホワイトリスト（`query.query_parameters.pluck(:name)`）でフィルタしてジョブに渡す
  - 受け入れ条件: `query.query_parameters` に存在しない名前のパラメータは無視されることを示すテストが通る
  - 注意: このタスクは [[10-query-execution]] のコントローラ実装と調整が必要
- [ ] (トピック10で実施) `spec/requests/queries/executions_spec.rb` にパラメータ付き実行のリクエストスペックを追加する（[[10-query-execution]] のスペックファイルに追記）
  - 受け入れ条件: パラメータ付きで `POST /queries/:id/executions` を送ると `QueryExecution` が作成されジョブがエンキューされる

### グループ6: System Spec
- [x] `spec/system/parameterized_query_spec.rb` を作成する（`rack_test` ドライバー）
  - 受け入れ条件: パラメータ付きQueryを開くとフォームが表示され、値を入力して送信できる

### グループ7: Brakeman確認
- [x] `bin/brakeman --no-pager` を実行し、パラメータ処理でSQL Injectionの警告が出ないことを確認する
  - 受け入れ条件: `Confidence: High` のSQL Injection警告がゼロ

## 動作確認
- [x] `{{ user_id:number }}` を含むSQLを保存し、実行フォームに数値フィールドが表示されることを確認する
- [x] `{{ created_at:date_range }}` を含むSQLを保存し、実行フォームに開始・終了の日付フィールドが2つ表示されることを確認する
- [ ] BigQuery実行時のSQLに `@user_id` が含まれ、`query_parameters` に型付きパラメータが渡されていることをログで確認する（実 BigQuery 実行はトピック10/手動。`Query#bound_sql` が `@name` を生成・`QueryParameter#to_bigquery_param` が型付き値を返すことは RSpec で担保済み）
- [ ] 文字列型パラメータにシングルクォートを含む値を入力し、クエリが正常に実行される（SQLインジェクションにならない）ことを確認する（実 BigQuery 実行はトピック10/手動。`bound_sql` が文字列連結を行わず `@param` のみ生成することは RSpec・Brakeman で担保済み）

## 未決事項・質問（解決済み）
- ✅ `number` 型 → **動的判定**。`QueryParameter#to_bigquery_param` が入力値を `Integer()` で試し、整数なら `Integer`（INT64 相当）、失敗時は `Float`（FLOAT64 相当）を返す。非数値は `ArgumentError`。
- ✅ `date_range` → **`@name_start` / `@name_end` 命名規則**で 2 つの `DATE` に展開（`to_bigquery_param` が `{ "name_start" => Date, "name_end" => Date }` を返す）。`bound_sql` は `{{ name:date_range }}` を `@name` に置換するため、SQL テンプレートは `BETWEEN @name_start AND @name_end` と記述する。フォームに案内文を表示。
- ✅ SQL 変更時の再描画 → **Stimulus**。`query_editor_controller` が SQL 変更時に `query-editor:change`（detail.sql）を dispatch し、`parameter_form_controller` が listen して `{{ }}` を再パース・フィールドを再描画する（CodeMirror の dispatchTransactions 経由、07 と疎結合）。
- ✅ パラメータ未入力 → **全パラメータ必須**（ボス確定）。`required` カラムは持たず、フォームは全フィールド HTML5 `required`、サーバ側も `Query#missing_parameter_values` で空が 1 つでもあれば拒否。NULL バインドは許容しない。

## 司令塔への申し送り（トピック10で接続）
- 実行コントローラ（`POST /queries/:id/executions`）はトピック10。本トピックで用意したモデルメソッドを使う:
  - `Query#permit_parameter_values(raw)` — `params[:query_params]` を定義済み名のみにホワイトリストフィルタ（未定義名は無視）。
  - `Query#missing_parameter_values(raw)` — 全パラメータ必須チェック（空の名前一覧。非空なら実行拒否）。
  - `Query#bound_sql` — `{{ name }}`→`@name` 変換済み SQL（BigQuery へ渡す）。
  - `QueryParameter#to_bigquery_param(value)` / `#bigquery_param_names` — 型付き値生成と展開名。
- 現状 `queries#show` は GET の `query_params` を受けて whitelist + 必須チェックの動作確認まで行う暫定実装。トピック10で本実行（ジョブ enqueue）に置き換える際は同メソッド群を再利用する。
