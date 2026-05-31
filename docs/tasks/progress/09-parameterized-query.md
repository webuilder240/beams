# 作業進捗ログ — トピック09: パラメータ化クエリ

> タスク `docs/tasks/09-parameterized-query.md` の作業ログ（時系列）。司令塔・Coder・Tester のアクションを記録。

- **ステータス**: 🔄進行中
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
