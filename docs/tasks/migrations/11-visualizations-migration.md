# マイグレーション確認用ドキュメント: `visualizations` テーブル作成

> トピック **11-visualization**（可視化・Chart.js）の最初の作業。`Visualization` モデルのテーブルを新規作成する。本ステップは**マイグレーション準備のみ**で、`db:migrate` は実行しない。
> **このドキュメントの承認後に `bin/rails db:migrate` を実行する。承認前は実行しない。**

- **対象マイグレーション**: `db/migrate/20260531140000_create_visualizations.rb`（クラス名 `CreateVisualizations`）
- **テーブル名**: `visualizations` / **モデル名**: `Visualization`（フラットなトップレベル）
- **作成日**: 2026-05-31
- **担当**: Coder
- **ステータス**: 承認待ち（未実行）

> **司令塔の確定方針（2026-05-31）**: `Query has_one :visualization, dependent: :destroy` / `Visualization belongs_to :query`（1クエリ1可視化）。可視化はクエリ結果（`QueryExecution#result` の `{schema:, rows:}`）を Chart.js で描画するための設定（軸・系列・チャート種別・表示モード）を保存する。チャート描画に使う結果データそのものは `query_executions` 側が保持するため、`visualizations` は設定値のみを持つ。

---

## 1. 追加するテーブル・カラム・制約・インデックス

### テーブル: `visualizations`（新規作成）

| カラム名 | 型 | NULL | デフォルト | 制約・備考 |
|----------|------|:----:|------------|-----------|
| `id` | integer (PK) | NOT NULL | 自動採番 | Rails 標準の主キー（自動付与） |
| `query_id` | integer (references) | NOT NULL | なし | `queries` への FK。**unique index** 付与（1クエリ1可視化） |
| `chart_type` | string | NOT NULL | `"line"` | 許可値 line/bar/pie/area/scatter/**counter**。アプリ層で validation |
| `x_column` | string | NULL 可 | なし | X 軸に使う結果カラム名。未設定時は NULL（counter 表示時は不使用） |
| `y_columns` | text | NULL 可 | なし | Y 軸カラム名の **JSON 配列を text 保存**（複数 Y 軸）。`serialize`/`store_accessor` で `Array` として透過利用（counter 表示時は不使用） |
| `series_column` | string | NULL 可 | なし | 系列分割に使う結果カラム名。未設定時は NULL（counter 表示時は不使用） |
| `display_mode` | string | NOT NULL | `"table"` | 許可値 table/chart。テーブル⇄チャート切替の現在モード |
| `counter_column` | string | NULL 可 | なし | **counter（カウンター）専用**。集計対象の結果カラム名。未設定時は NULL |
| `counter_aggregation` | string | NOT NULL | `"sum"` | **counter 専用**。集計方法。許可値 sum/avg/count/min/max。アプリ層で validation |
| `created_at` | datetime | NOT NULL | なし | `t.timestamps` により自動付与 |
| `updated_at` | datetime | NOT NULL | なし | `t.timestamps` により自動付与 |

### インデックス

| インデックス名 | 対象カラム | 種別 | 目的 |
|----------------|-----------|------|------|
| `index_visualizations_on_query_id` | `query_id` | **unique** | `has_one :visualization`（1クエリ1可視化）を DB 制約でも担保。`query.visualization` 取得・FK 結合 |

---

## 2. 各カラム・インデックスの目的・設計判断

- **`query_id`（references / FK / NOT NULL / unique index）**
  可視化は必ず特定の `Query` に紐づく。`belongs_to :query`（`optional: false` デフォルト）に対応し DB でも NOT NULL。`t.references ... foreign_key: true` で FK 制約と index を同時に付与する（既存 `query_executions` / `query_parameters` と同方式）。`has_one` 関連のため **unique** を付与し、1 クエリに 2 件以上の可視化が作られない保証を DB で担保する（論点①参照）。

- **`chart_type`（string / NOT NULL / default `"line"`）**
  チャート種別。許可値は line/bar/pie/area/scatter/**counter**（6種）。
  - **default を `"line"` にした理由**: doc §Visualization モデルの指定どおり。可視化を新規作成した時点で最も汎用的な折れ線をフォールバックにする。未指定でレコードを作っても安全側（line）に倒れる。
  - **NOT NULL の理由**: チャート種別のない可視化は描画できない。アプリ層（許可リスト validation）でも担保するが、DB 制約で nil を禁止し安全網とする。
  - 許可値の担保はアプリ層（`validates :chart_type, inclusion: ...`）で行い、DB の CHECK 制約は設けない（既存テーブルと同方針）。
  - **`counter`（カウンター・Redash 風）について**: 単一の集計値を大きく表示するビジュアライゼーション。X/Y 軸・系列は使わず、専用の `counter_column` / `counter_aggregation` を使う（別系統設定）。

- **`counter_column`（string / NULL 可）/ `counter_aggregation`（string / NOT NULL / default `"sum"`）— counter 専用**
  `chart_type: "counter"` のときのみ意味を持つ設定。`counter_column` は集計対象の結果カラム名、`counter_aggregation` は集計方法（許可値 sum/avg/count/min/max）。
  - **集計はアプリ層で行う（BigQuery 再クエリなし）**: counter の集計値は **BigQuery に再クエリせず、取得済み結果（`QueryExecution#result` の `rows`）に対してアプリ層（後続の `Visualization` モデルメソッド or helper）で SUM/AVG/COUNT/MIN/MAX を計算**する。再課金・再フェッチを避け、表示用 blob から即座に算出する方針（topic-10 の「表示用先頭 N 行 blob」を入力とする）。
  - **`counter_aggregation` の default を `"sum"` にした理由**: ボス決定。最も一般的な「合計」をフォールバックにする。NOT NULL とし、許可値（sum/avg/count/min/max）はアプリ層 validation で担保（DB CHECK は設けない）。
  - **`counter_column` を NULL 可にした理由**: counter 以外（line 等）では使わず、counter 選択直後も未設定があり得るため NULL を許容する。
  - **x/y 軸とは別系統である理由**: counter 表示は軸の概念を持たない単一値表示。`x_column`/`y_columns`/`series_column` と混在させず、`counter_*` 専用カラムに分離することで「counter 時は counter_*、chart 時は x/y/series」という排他的な設定の意図を明確にする。

- **`x_column`（string / NULL 可）**
  X 軸に使う結果カラム名。可視化作成直後やユーザー未設定時は NULL（論点③参照）。

- **`y_columns`（text / NULL 可、JSON 配列を保存）**
  Y 軸カラム名の配列。複数 Y 軸（`select multiple`）に対応するため**配列**を保持する。
  - **`text` + JSON にした理由**: doc の `string` 表記は「JSON 配列を text 保存」の意。カラム名は短いが複数件を可変長で持つため、固定長になりがちな `string`（SQLite では実害は小さいが）より、配列 JSON の保存先として `text` が適切。モデルで `serialize :y_columns, coder: JSON`（または `store`/`store_accessor`）を介して透過的に `Array` を読み書きする（論点②参照）。
  - **NULL 可の理由**: 可視化作成直後・Y 軸未設定時は値がない。空配列 `[]` ではなく NULL を許容し、未設定を表現できるようにする。

- **`series_column`（string / NULL 可）**
  系列（凡例の分割）に使う結果カラム名。系列分割しない場合は NULL（論点③参照）。

- **`display_mode`（string / NOT NULL / default `"table"`）**
  テーブル表示かチャート表示かの現在モード。
  - **default を `"table"` にした理由**: doc §Visualization モデルの指定どおり。可視化未設定（軸未指定）でも安全に開ける「テーブル表示」を初期状態にする。チャートは軸設定後に意味を持つため、初期は table が自然。
  - **NOT NULL の理由**: 表示モードのない可視化はビューが分岐できない。許可値（table/chart）はアプリ層 validation で担保。

- **`created_at` / `updated_at`**
  `t.timestamps` による標準のタイムスタンプ。

### あえて今回入れていないもの

- **DB の CHECK 制約（`chart_type` / `display_mode` / `counter_aggregation` の許可値）**: アプリ層（`inclusion` validation）で担保する方針（既存テーブルと同様、SQLite + アプリ層担保）。
- **`y_columns` のスキーマ検証**: 結果カラム名と一致するかはアプリ層・UI 側で扱い、DB では検証しない。
- **結果データ本体のカラム**: 描画に使う `{schema:, rows:}` は `query_executions.result_blob`（圧縮 blob）が保持する。可視化は設定値のみで、結果を二重持ちしない。

---

## 3. モデル構成（実装段階で作成、本ドキュメントは設計の明記）

マイグレーション承認・実行後の後続実装で、以下を用意する（本ステップでは未作成、参考情報）。

`app/models/visualization.rb`

```ruby
class Visualization < ApplicationRecord
  CHART_TYPES = %w[line bar pie area scatter counter].freeze
  DISPLAY_MODES = %w[table chart].freeze
  AGGREGATIONS = %w[sum avg count min max].freeze

  belongs_to :query

  serialize :y_columns, coder: JSON # ["col_a", "col_b"] を透過的に Array で扱う

  validates :chart_type, inclusion: { in: CHART_TYPES }
  validates :display_mode, inclusion: { in: DISPLAY_MODES }
  validates :counter_aggregation, inclusion: { in: AGGREGATIONS }
  # 軸→Chart.js data 組み立て・counter 集計（rows への SUM/AVG/COUNT/MIN/MAX）等は
  # 後続タスクで TDD 実装。counter 集計は BigQuery 再クエリせず取得済み rows に対して計算。
end
```

`app/models/query.rb` に `has_one :visualization, dependent: :destroy` を追加（後続タスク）。

> 補足（名称読み替え・実装確認結果）:
> - 可視化が参照する結果は `QueryExecution#result`（`app/models/query_execution.rb`）。`result_blob` を Inflate して `{ schema: Array, rows: Array }` を返し、blob 未保存/空は **nil**。doc の `QueryExecution#result_data` は本実装の `result` を指す。
> - CSV エクスポートは可視化側で生成せず、トピック10 の経路にリンクするだけ。実パスは `GET /queries/:query_id/executions/latest/csv`（`Queries::Executions::CsvExportsController#show`、route helper `latest_csv_query_executions_path(query)`）。最新成功実行の `storage/csv/<id>.csv.gz` を `send_file ... x_sendfile: true` で配信する。

---

## 4. 実行するマイグレーションコマンド（承認後に実行）

```bash
bin/rails db:migrate
```

- 影響 DB: development（`storage/development.sqlite3`）、test（`storage/test.sqlite3`）
- 実行後、`db/schema.rb` が `version: 20260531140000` に更新され、`visualizations` テーブル定義が反映される。

テスト DB を schema から再構築する場合:

```bash
bin/rails db:test:prepare
```

---

## 5. ロールバック方法

直前のマイグレーション（この `create_visualizations`）を取り消す:

```bash
bin/rails db:rollback
```

- `change` メソッドで定義しているため、`create_table` は自動的に逆操作（`drop_table`）でロールバックされる（unique index も併せて削除）。
- ロールバック後は `db/schema.rb` の version が直前（`20260531130000`、`query_executions` まで）に戻る。

特定バージョンまで戻す場合:

```bash
bin/rails db:migrate:down VERSION=20260531140000
```

---

## 6. 影響範囲

- **development / test**: 新規テーブル追加のみ。既存テーブル（`queries` 等）への変更・データ移行はなし（破壊的変更なし）。`queries` への FK を張るが、`queries` 側の定義は変更しない（`has_one` 関連はモデル側のみで、`queries` テーブルにカラム追加は不要）。
- **production**: 本ステップでは production への適用は行わない。production（`storage/production.sqlite3`、`db/migrate` パス）への反映は別途デプロイ時に検討する（Kamal の運用フローに従う）。
- **既存テスト**: 既存テーブルを変更しないため、既存スペックへの影響はなし。
- **後続実装への依存**: 本マイグレーションは純粋なスキーマ追加で、暗号化キーや外部 API に依存しない。

---

## 7. マイグレーションファイルの内容（転記）

`db/migrate/20260531140000_create_visualizations.rb`

```ruby
class CreateVisualizations < ActiveRecord::Migration[8.1]
  def change
    create_table :visualizations do |t|
      t.references :query, null: false, foreign_key: true, index: { unique: true }
      t.string :chart_type, null: false, default: "line"
      t.string :x_column
      t.text :y_columns
      t.string :series_column
      t.string :display_mode, null: false, default: "table"
      t.string :counter_column
      t.string :counter_aggregation, null: false, default: "sum"

      t.timestamps
    end
  end
end
```

---

## 8. 承認をお願いしたい内容・論点

### 承認をお願いしたい内容

- `visualizations` テーブルを新規作成する（破壊的変更なし）
- カラム: `query_id`(references, FK, NOT NULL, unique) / `chart_type`(string, NOT NULL, default `"line"`、許可値 line/bar/pie/area/scatter/**counter**) / `x_column`(string, NULL) / `y_columns`(text, NULL) / `series_column`(string, NULL) / `display_mode`(string, NOT NULL, default `"table"`) / **`counter_column`(string, NULL)** / **`counter_aggregation`(string, NOT NULL, default `"sum"`、許可値 sum/avg/count/min/max)** / `created_at` / `updated_at`
- インデックス: `query_id`（**unique**、`has_one` 担保）
- 適用先は development / test の 2 DB のみ（production は別途）

### 論点（司令塔に確認したい点 + Coder の推奨）

1. **`query_id` に unique index を付けること（推奨: 付ける）**
   `Query has_one :visualization`（1クエリ1可視化）なので、DB レベルでも 1 クエリに複数の可視化が作られないことを保証したい。`VisualizationsController#update` は upsert（`query.visualization || query.build_visualization`）でレコードを更新する設計（doc §VisualizationsController）であり、競合下でも一意制約があれば重複作成を防げる。**Coder 推奨: unique index を付与する**（マイグレーションでは `index: { unique: true }` を採用済み）。複数可視化を将来許容する計画があれば外す。

2. **`y_columns` を text + JSON にする判断（推奨: text + JSON）**
   doc のカラム表は `y_columns:string`（JSON 配列を text 保存）と注記。複数 Y 軸を可変長配列で持つため、`string` ではなく **`text`** を採用し、モデルで `serialize :y_columns, coder: JSON` を介して `Array` として透過利用する。**Coder 推奨: text + JSON serialize**。`store_accessor` ではなく単一カラムの `serialize` が配列保存に素直。

3. **`x_column` / `series_column` / `y_columns` を nullable にする是非（推奨: nullable のまま）**
   可視化レコードは「テーブル表示（`display_mode: "table"`）」で軸未設定のまま作成・存在し得る（チャート未設定でもテーブルは見られる）。軸を必須にすると未設定状態を表現できず、初期作成・table モードと矛盾する。**Coder 推奨: 3カラムとも NULL 可**。チャート描画時に軸未設定なら UI 側で「軸を選んでください」と促す（DB では強制しない）。

4. **`chart_type` / `display_mode` の default 値（推奨: `"line"` / `"table"`）**
   doc §Visualization モデルの指定どおり `chart_type` default `"line"`、`display_mode` default `"table"`。可視化を新規作成した直後でも、軸未設定で安全に開ける「table 表示・line チャート種別」をフォールバックにする。両カラムは NOT NULL（許可値はアプリ層 validation で担保）。**Coder 推奨: この default で確定**。

5. **`chart_type` に `counter` を追加（ボス追加要件・確定）**
   Redash 風「単一集計値を大きく表示」の counter を許可値に追加し、許可リストは line/bar/pie/area/scatter/**counter** の6種。counter は x/y 軸・系列とは**別系統**の `counter_column` / `counter_aggregation` で設定する。**Coder 推奨: counter は専用 2 カラムに分離**（x/y と混在させない）。

6. **`counter_aggregation` の default と許可値（推奨: default `"sum"`、許可値 sum/avg/count/min/max）**
   集計方法の default を `"sum"`（最も一般的な合計）とし、NOT NULL。許可値 sum/avg/count/min/max はアプリ層 validation（`AGGREGATIONS`）で担保し、DB CHECK は設けない。**Coder 推奨: この default・許可値で確定**。

7. **counter の集計はアプリ層計算（BigQuery 再クエリなし）（推奨: アプリ層）**
   counter の集計値は **BigQuery に再クエリせず、取得済み結果（`QueryExecution#result` の `rows`）に対してアプリ層で計算**する（再課金・再フェッチ回避）。**Coder 推奨: アプリ層計算で確定**。
   - **未確定（DB 設計には影響なし・後続実装で確定）**: `count` の意味を「`counter_column` の非 NULL 件数」とするか「全行数（COUNT(*) 相当）」とするか。スキーマには影響しないため、後続のモデルメソッド実装時に確定する。

**この内容で `bin/rails db:migrate` を実行してよいか、承認をお願いします（本ステップではマイグレーション準備のみ・未実行）。**
