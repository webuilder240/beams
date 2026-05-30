# トピック09: パラメータ化クエリ

> `{{ name }}` 記法でSQLにパラメータを埋め込み、BigQueryネイティブバインド（`@param`）で安全に実行する。計画書 §4.5 に対応。

- **ステータス**: 未着手
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
- [ ] `spec/models/query_parameter_spec.rb` にパース機能のテストを先に書く（失敗するRSpecを先に用意する）
  - 受け入れ条件: `Query#parameters` が `[{ name: "user_id", type: :number }]` を返すテストが **red** で存在する
- [ ] `Query#parameters` インスタンスメソッドを `app/models/query.rb` に実装する — `{{ name }}`, `{{ name:number }}`, `{{ name:date }}`, `{{ name:date_range }}` 記法をパースし、`[{ name: String, type: Symbol }]` の配列を返す
  - 受け入れ条件: `query.parameters` が `[{ name: "user_id", type: :number }]` を返すテストが通る
- [ ] 型の対応表を定数として `Query` または `QueryParameter` に定義する (`SUPPORTED_TYPES = %i[string number date date_range]`)
  - 受け入れ条件: 不明な型記法（例: `{{ x:unknown }}`）は `:string` にフォールバックするか、パースエラーとして返すかをテストで明確にする
- [ ] `spec/models/query_parameter_spec.rb` を完成させる（`spec/models/` 以下に配置）
  - 受け入れ条件: パラメータなし・1個・複数・型4種・同名重複・不正記法のケースをカバーし、テストが **green** になるまで完了にしない

### グループ2: パラメータ定義の保存モデル
- [ ] `query_parameters` テーブルを作成するマイグレーション (`db/migrate/YYYYMMDDHHMMSS_create_query_parameters.rb`) を作成する — カラム: `query_id:references`, `name:string`, `param_type:string`, `position:integer`
  - 受け入れ条件: `bin/rails db:migrate` が通る
- [ ] `app/models/query_parameter.rb` を作成する — `belongs_to :query`, バリデーション（`name` 必須・英数字アンダースコアのみ, `param_type` が4種内）
  - 受け入れ条件: 不正な `name`（スペース含む等）・不正な `param_type` でバリデーションエラーになるモデルテストが通る
- [ ] `app/models/query.rb` に `has_many :query_parameters, dependent: :destroy` と、SQL保存時にパラメータを自動同期するメソッド（`sync_parameters!`）を追加する
  - 受け入れ条件: `query.update(sql: "SELECT {{ x }}")` 後に `query.query_parameters.pluck(:name)` が `["x"]` になるテストが通る
- [ ] `spec/models/query_parameter_spec.rb` を作成する
  - 受け入れ条件: バリデーション・関連のテストをカバー
- [ ] `spec/models/query_spec.rb` に `sync_parameters!` のテストを追加する
  - 受け入れ条件: SQL変更でパラメータが追加・削除・更新される3ケースをカバー

### グループ3: `{{ name }}` → `@name` SQL変換とパラメータバインダー（TDD）
- [ ] `spec/models/query_spec.rb` に `Query#bound_sql` のテストを先に書く（失敗するRSpecを先に用意する）
  - 受け入れ条件: `query.bound_sql` が `"SELECT @user_id"` を返すテストが **red** で存在する。文字列連結パスが存在しないことをテストで担保する
- [ ] `Query#bound_sql` インスタンスメソッドを `app/models/query.rb` に実装する — SQL内の `{{ name }}` を `@name` に置換し、変換後SQLを返す
  - 受け入れ条件: `query.bound_sql` が `"SELECT @user_id"` を返すテストが通る
- [ ] `spec/models/query_parameter_spec.rb` に `QueryParameter#to_bigquery_param` のテストを先に書く（失敗するRSpecを先に用意する）
  - 受け入れ条件: 型4種それぞれのバインドオブジェクト生成テストが **red** で存在する
- [ ] `QueryParameter#to_bigquery_param` インスタンスメソッドを `app/models/query_parameter.rb` に実装する — `{ name, type, value }` から `Google::Cloud::Bigquery::QueryParameter` を生成する
  - 型マッピング: `string` → `STRING`, `number` → `FLOAT64`（または`INT64`、値が整数か判定）, `date` → `DATE`, `date_range` → 開始・終了を2つの `DATE` パラメータに展開
  - 受け入れ条件: 型4種・不正値（数値フィールドに文字列を渡す等）のテストが **green** になるまで完了にしない（`spec/models/` 以下に配置）

### グループ4: 実行時フォームUI
- [ ] `app/views/queries/_parameter_form.html.erb` パーシャルを作成する — `query.query_parameters` を元に型別フォームフィールドを動的レンダリングする
  - `string`: `<input type="text">`
  - `number`: `<input type="number">`
  - `date`: `<input type="date">`
  - `date_range`: `<input type="date">` × 2（開始・終了）
  - 受け入れ条件: パラメータを持つQueryの実行画面でフォームが表示される
- [ ] クエリ実行フォーム（`app/views/queries/show.html.erb` 相当）にパラメータフォームを組み込む
  - 受け入れ条件: パラメータなしのQueryではフォームが表示されない。パラメータありのQueryでは必須フィールドが空のまま送信できない（HTML5 `required`）
- [ ] SQLエディタのSQL変更時にTurbo Frame（またはStimulusコントローラ）でパラメータフォームを再描画する仕組みを実装する (`app/javascript/controllers/parameter_form_controller.js`)
  - 受け入れ条件: SQL内の `{{ foo }}` を追加・削除するとフォームフィールドが動的に増減する（System Specで確認）

### グループ5: コントローラへのパラメータ受け渡し
- [ ] `app/controllers/queries/executions_controller.rb`（[[10-query-execution]] で作成予定）のパラメータ受け取りロジックを設計する — `params[:query_params]` をホワイトリスト（`query.query_parameters.pluck(:name)`）でフィルタしてジョブに渡す
  - 受け入れ条件: `query.query_parameters` に存在しない名前のパラメータは無視されることを示すテストが通る
  - 注意: このタスクは [[10-query-execution]] のコントローラ実装と調整が必要
- [ ] `spec/requests/queries/executions_spec.rb` にパラメータ付き実行のリクエストスペックを追加する（[[10-query-execution]] のスペックファイルに追記）
  - 受け入れ条件: パラメータ付きで `POST /queries/:id/executions` を送ると `QueryExecution` が作成されジョブがエンキューされる

### グループ6: System Spec
- [ ] `spec/system/parameterized_query_spec.rb` を作成する（`rack_test` ドライバー）
  - 受け入れ条件: パラメータ付きQueryを開くとフォームが表示され、値を入力して送信できる

### グループ7: Brakeman確認
- [ ] `bin/brakeman --no-pager` を実行し、パラメータ処理でSQL Injectionの警告が出ないことを確認する
  - 受け入れ条件: `Confidence: High` のSQL Injection警告がゼロ

## 動作確認
- [ ] `{{ user_id:number }}` を含むSQLを保存し、実行フォームに数値フィールドが表示されることを確認する
- [ ] `{{ created_at:date_range }}` を含むSQLを保存し、実行フォームに開始・終了の日付フィールドが2つ表示されることを確認する
- [ ] BigQuery実行時のSQLに `@user_id` が含まれ、`query_parameters` に型付きパラメータが渡されていることをログで確認する
- [ ] 文字列型パラメータにシングルクォートを含む値を入力し、クエリが正常に実行される（SQLインジェクションにならない）ことを確認する

## 未決事項・質問
- `number` 型の BigQuery型は `FLOAT64` と `INT64` のどちらにするか（入力値が整数かどうかで動的判定するか、固定にするか）。
- `date_range` 型は `@name_start` / `@name_end` の命名規則で2パラメータに展開する方針でよいか。SQLテンプレート側の記述方法（例: `BETWEEN @created_at_start AND @created_at_end` の書き方をユーザーに案内する必要がある）。
- SQL変更時のパラメータフォーム再描画をStimulusで行う場合、エディタのCodeMirrorイベントとどう統合するか（[[07-query-editor]] との調整が必要）。
- パラメータ未入力での実行を許可するか（NULL バインドを許容するか、必須バリデーションをサーバー側でも行うか）。
