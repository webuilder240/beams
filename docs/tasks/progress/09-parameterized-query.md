# 作業進捗ログ — トピック09: パラメータ化クエリ

> タスク `docs/tasks/09-parameterized-query.md` の作業ログ（時系列）。司令塔・Coder・Tester のアクションを記録。

- **ステータス**: ✅実装完了（Tester引き継ぎ待ち）
- **担当**: Coder

## 司令塔メモ（着手時の判断・未決事項の決定）

- **新規マイグレーション必要**: `query_parameters` テーブル → マイグレーション承認ゲート。
- **未決事項の決定（司令塔）**:
  - `number` の BigQuery 型: **動的判定**（入力値が整数なら `INT64`、それ以外は `FLOAT64`）。
  - `date_range`: **`@name_start` / `@name_end`** の2パラメータに展開。UIヒントで `BETWEEN @x_start AND @x_end` の書き方を案内。
  - SQL変更時のパラメータフォーム再描画: **Stimulus**（クエリエディタのSQL変更イベントを `parameter_form_controller` が受けて再描画。CodeMirror連携）。
  - パラメータ未入力: **必須**（HTML5 `required` ＋ サーバ側バリデーション）。NULL バインドは許容しない（MVP）。
  - 不正な型記法（`{{ x:unknown }}`）は **`:string` にフォールバック**（パースエラーにしない）。
- **命名読み替え**: BigQueryクライアントは `Bigquery::Connection#bigquery`。`query_parameters:` オプションに型付きパラメータを渡す。
- グループ5（executions コントローラへのパラメータ受け渡し）は **トピック10と調整**。本トピックでは「ホワイトリスト（`query.query_parameters.pluck(:name)`）でフィルタする設計・ロジック」を用意し、実行コントローラ本体は10で実装。

## 時系列ログ

### 2026-05-31

- **司令塔**: トピック08完了を受け、依存（07・04）充足済みのトピック09に着手。新規 Coder をアサイン。`query_parameters` テーブルのマイグレーションが必要 → 承認ゲート。確認用ドキュメント作成を指示。
- **Coder→司令塔**: `query_parameters` マイグレーション＋確認ドキュメント作成。論点3点（(query_id,name) unique / position nullable / param_type string）を提起。司令塔: いずれも妥当。
- **司令塔→人間**: `query_parameters` マイグレーション承認を依頼。
- **人間→司令塔**: 承認保留 → **(1) `required`（必須フラグ）カラムを追加。(2) `position` は不要なので削除。**
- **司令塔（確定）**: スキーマ修正。`position` を削除（表示順はSQL出現順＝id順で代替）。`required`（boolean, NOT NULL, default true）を追加。`required` がフォームの HTML5 `required` 属性とサーバ側必須バリデーションを駆動（required=false は空欄許容）。ボスの具体指定＝改訂版マイグレーションの承認とみなし、修正適用後に migrate を許可。
- **司令塔→Coder**: マイグレーション修正（position削除・required追加）＋確認doc更新 → migrate 実行 → トピック09 本実装（TDD）を指示。
- **人間→司令塔（訂正）**: **`required` カラムも不要**。未入力パラメータがある場合は全てエラーにする（＝全パラメータ必須）。
- **司令塔（最終確定）**: スキーマは `query_id`(FK,NOT NULL) / `name`(NOT NULL) / `param_type`(NOT NULL) / timestamps ＋ `(query_id,name)` unique のみ（**position も required も無し**）。挙動: **全パラメータ必須**。実行フォームは全フィールドに HTML5 `required`、サーバ側でも未入力（blank）パラメータがあれば実行を拒否しエラー表示。Coder に訂正指示。

### 2026-05-31（続き・Coder 本実装）

- **マイグレーション（最終スキーマ・承認済み）**: `db/migrate/20260531120000_create_query_parameters.rb` を `query_id`(references,FK,NOT NULL) / `name`(NOT NULL) / `param_type`(NOT NULL) / timestamps ＋ `(query_id,name)` unique のみに修正（position/required 無し）。確認doc `docs/tasks/migrations/09-query-parameters-migration.md` も「position なし・required なし・全パラメータ必須」に更新。`bin/rails db:migrate` ＋ `db:test:prepare` 実行 → `db/schema.rb` を `version: 20260531120000` に更新。commit「query_parameters マイグレーション作成」。
- **パーサー（TDD red→green）**: `Query#parameters`（`PARAMETER_PATTERN` で `{{ name:type }}` をパース、`[{name:,type:}]`）。不明型→`:string` フォールバック、同名は最初の出現に正規化、出現順維持、不正識別子（`{{ 123abc }}`）は無視。`spec/models/query_spec.rb` にパラメータなし/1個/複数/型4種/重複/不正記法を網羅。
- **QueryParameter モデル（TDD）**: `app/models/query_parameter.rb`。`SUPPORTED_TYPES = %i[string number date date_range]`、`belongs_to :query`、`name`（presence＋`/\A\w+\z/`）、`param_type`（inclusion）、`(query_id,name)` uniqueness。`#to_bigquery_param(value)`（string→String / number→整数判定で Integer/Float / date→Date / date_range→`{name_start=>Date,name_end=>Date}`、不正値は `ArgumentError`）、`#bigquery_param_names`（date_range は start/end 展開）。**`Google::Cloud::Bigquery::QueryParameter` クラスは gem に存在しないため、SDK が `query(..., params:, types:)` で受け取れる Ruby ネイティブ値（String/Integer/Float/Date/Hash）を返す方針に読み替え**（実バインドはトピック10で `bigquery.query` に渡す）。`spec/models/query_parameter_spec.rb` で網羅。
- **sync/bound（TDD）**: `Query#sync_parameters!`（after_save、`(query_id,name)` キーで upsert・SQL から消えた名前は削除・型更新）。`has_many :query_parameters, -> { order(:id) }`（出現順＝作成順）。`Query#bound_sql`（`{{name}}`→`@name`、**文字列連結なし**＝テストで担保、date_range も `@name` に置換しテンプレ側で `@name_start/@name_end` 参照）。spec で追加/削除/更新/全消去をカバー。
- **グループ5（受け渡しロジック・トピック10へ申し送り）**: `Query#permit_parameter_values(raw)`（定義済み名のみホワイトリスト、未定義は無視）／`Query#missing_parameter_values(raw)`（全パラメータ必須、空が1つでもあれば名前一覧を返す。date_range は start/end どちらか空なら欠落扱い）。実行コントローラ本体はトピック10。
- **実行時フォームUI**: `app/views/queries/_parameter_form.html.erb`（型別: text/number/date/date×2、全フィールド `required`、date_range は `name[start]`/`name[end]`）。`queries#show` でパラメータありのとき表示・パラメータなしは非表示。show は GET の `query_params` を受けて whitelist＋必須チェックの動作確認（実本送信＝ジョブ enqueue はトピック10）。
- **動的再描画（Stimulus・07連携）**: `query_editor_controller.js` が SQL 変更時に `query-editor:change`（detail.sql）を dispatch。`parameter_form_controller.js` がそれを listen し `{{ }}` を再パースしてフィールドを動的に増減。`_form.html.erb` にプレビュー枠を追加。
- **テスト**: `spec/system/parameterized_query_spec.rb`（rack_test: 表示/入力送信/必須欠落でエラー/非パラメータで非表示/date・date_range フィールド/編集フォームにプレビュー枠）、`spec/system/parameterized_query_js_spec.rb`（js: true: SQL 編集で foo/bar フィールドが動的増減・全消去で消える）、`spec/requests/queries_spec.rb` にパラメータ表示・whitelist・必須欠落の request spec 追加。
- **品質ゲート（全て green/クリーン）**: `bundle exec rspec` = **272 examples / 0 failures**、SimpleCov **99.56%**（≥85%）。`bin/rubocop` 0 offense。`bin/brakeman --no-pager` **警告0**（SQL Injection 警告ゼロ＝`bound_sql` は `@param` のみ・文字列連結なし）。`bin/importmap audit` 脆弱性0。
- **タスク doc / overview**: `09-parameterized-query.md` のグループ1〜4・6・7・グループ5の設計ロジック分を完了に・ステータス「完了」、未決事項4点を解決済みに反映。`00-overview.md` 表の 09 を「完了」に更新。executions の `POST /executions` request spec・実 BigQuery 実行確認はトピック10/手動として未チェックで明記。
- **追加マイグレーション**: なし（query_parameters の範囲内）。
- **Coder→司令塔**: 実装完了。Tester へ引き継ぎ。
