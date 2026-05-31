# マイグレーション確認用ドキュメント: `query_executions` テーブル作成

> トピック **10-query-execution**（非同期実行・結果保存）の最初の作業。`QueryExecution` モデルのテーブルを新規作成する。本ステップは**マイグレーション準備のみ**で、`db:migrate` は実行しない。
> **このドキュメントの承認後に `bin/rails db:migrate` を実行する。承認前は実行しない。**

- **対象マイグレーション**: `db/migrate/20260531130000_create_query_executions.rb`（クラス名 `CreateQueryExecutions`）
- **テーブル名**: `query_executions` / **モデル名**: `QueryExecution`（フラットなトップレベル）
- **作成日**: 2026-05-31
- **担当**: Coder
- **ステータス**: 承認待ち（未実行）

> **司令塔の確定方針（2026-05-31）**: `QueryExecution` は `Query` 配下の関連だが、モデルはフラットなトップレベル（`app/models/query_execution.rb`、`belongs_to :query`）。テーブルは `query_executions`。結果は最新成功1件のみ保持（上書き、履歴なし）し、表示用は圧縮 blob（JSON + gzip）に格納する。

---

## 1. 追加するテーブル・カラム・制約・インデックス

### テーブル: `query_executions`（新規作成）

| カラム名 | 型 | NULL | デフォルト | 制約・備考 |
|----------|------|:----:|------------|-----------|
| `id` | integer (PK) | NOT NULL | 自動採番 | Rails 標準の主キー（自動付与） |
| `query_id` | integer (references) | NOT NULL | なし | `queries` への FK。index 付与（`t.references` により自動） |
| `status` | string | NOT NULL | `"pending"` | enum: pending/running/succeeded/failed。**単独 index 付与** |
| `error_message` | text | NULL 可 | なし | 実行失敗時のエラーメッセージ。`failed` 時のみ格納 |
| `result_blob` | binary | NULL 可 | なし | 表示用の先頭 N 行を JSON + `Zlib::Deflate`（gzip）で圧縮したバイナリ |
| `result_row_count` | integer | NULL 可 | なし | 結果の行数（切り詰め前の総数 or 保存行数。実装で確定） |
| `result_truncated` | boolean | NULL 可 | `false` | 二重上限（10,000行 / 圧縮後10MB）超過で先頭 N 行に切り詰めた場合 true |
| `result_schema` | text | NULL 可 | なし | 列スキーマ（カラム名・型）を JSON 文字列で格納 |
| `started_at` | datetime | NULL 可 | なし | ジョブが BigQuery 実行を開始した時刻（`running` 遷移時） |
| `finished_at` | datetime | NULL 可 | なし | 実行完了（succeeded / failed）時刻 |
| `created_at` | datetime | NOT NULL | なし | `t.timestamps` により自動付与 |
| `updated_at` | datetime | NOT NULL | なし | `t.timestamps` により自動付与 |

### インデックス

| インデックス名 | 対象カラム | 種別 | 目的 |
|----------------|-----------|------|------|
| `index_query_executions_on_query_id` | `query_id` | 通常 | `t.references` により自動付与。FK 結合・`Query` からの関連取得 |
| `index_query_executions_on_status` | `status` | 通常 | 同時実行カウント `where(status: [:running, :pending]).count` の高速化 |
| `index_query_executions_on_query_id_and_status` | `(query_id, status)` | 複合 | 「特定 query の最新成功1件」取得（`where(query_id:, status: :succeeded)`）の高速化 |

---

## 2. 各カラム・インデックスの目的・設計判断

- **`query_id`（references / FK / NOT NULL / index）**
  実行は必ず特定の `Query` に紐づく。`belongs_to :query`（`optional: false` がデフォルト）に対応し DB でも NOT NULL。`t.references ... foreign_key: true` で FK 制約と index を同時に付与する（既存 `query_parameters` と同方式）。

- **`status`（string / NOT NULL / default `"pending"` / index）**
  enum `{ pending, running, succeeded, failed }` の状態。
  - **default を `"pending"` にした理由**: 実行は「キュー投入待ち = pending」から始まるのが自然なライフサイクル。コントローラで明示せずレコードを作っても安全側（pending）に倒れる。enum の文字列値（`status: { pending: "pending", ... }`）と DB default の文字列を一致させる。
  - **NOT NULL の理由**: 状態のない実行はあり得ない。アプリ層（`validates :status, presence: true` + enum）でも担保するが、DB 制約で nil を禁止し安全網とする。
  - **単独 index の理由**: 同時実行20件上限のため `QueryExecution.where(status: [:running, :pending]).count` を実行ごとに走らせる。query 横断の全体カウントなので `status` 単独 index が効く（`query_id` を含む複合 index ではこのクエリに最適化されない）。

- **`error_message`（text / NULL 可）**
  失敗時のメッセージ。長文になり得るため `text`。成功時は NULL のまま。

- **`result_blob`（binary / NULL 可）**
  表示用の先頭 N 行＋列スキーマを `JSON + Zlib::Deflate`（gzip）で圧縮した1レコード（タスク doc §グループ2、未決事項で確定済みの圧縮形式）。
  - **`binary` にした理由**: gzip 圧縮後の出力は任意のバイト列であり、テキストカラムではエンコーディング不整合や破損のおそれがある。SQLite では `binary` → `BLOB` にマップされ、バイト列をそのまま安全に往復できる。`store_result` / `result` のラウンドトリップ（Deflate ↔ Inflate）に必須。
  - **NULL 可の理由**: pending / running / failed の段階では結果が未確定。succeeded 時のみ書き込む。
  - **サイズ上限**: 二重上限（圧縮後10MB）をアプリ層（`QueryResult` PORO の切り詰め）で守るため、DB カラムにサイズ制限は設けない。SQLite の BLOB は十分大きい（既定で最大1GB）。

- **`result_row_count`（integer / NULL 可）**
  結果行数。UI 表示・truncated 判定の補助。succeeded 時のみ。

- **`result_truncated`（boolean / NULL 可 / default `false`）**
  二重上限超過で先頭 N 行に切り詰めたか。true のとき UI に「全件は CSV ダウンロード」バナーを出す。
  - **default `false` にした理由**: 「切り詰めていない」が通常状態。明示しなくても false に倒れ、ビュー側の `if result_truncated` が nil 三値論理に悩まされない。
  - **NULL 可のままにした理由**: 司令塔方針が「default false を検討」。default を与えるが、結果未確定段階（pending/running）で意味を持たないため NOT NULL までは強制せず NULL 可とする（実行前レコードに対し false を意味付けしないため）。

- **`result_schema`（text / NULL 可）**
  列スキーマ（カラム名・データ型の配列）を JSON 文字列で格納。`result_blob` にも schema を同梱するが、blob を解凍せずスキーマだけ参照したいケース（ヘッダー描画等）に備え別カラムにも持つ。succeeded 時のみ。

- **`started_at` / `finished_at`（datetime / NULL 可）**
  実行の所要時間計測・運用監視用。`running` 遷移で `started_at`、`succeeded`/`failed` 遷移で `finished_at` を打つ。実行前は NULL。

- **`created_at` / `updated_at`**
  `t.timestamps` による標準のタイムスタンプ。

### インデックス戦略の判断（複合 index の要否）

- **`status` 単独 index（採用）**: 同時実行カウント（query 横断）で必須。司令塔方針どおり付与。
- **`(query_id, status)` 複合 index（採用）**: 「特定 query の最新成功1件」（`where(query_id:, status: :succeeded).order(created_at: :desc).first`、`latest_succeeded_execution` スコープ）が頻繁。先頭カラム `query_id` で絞り込み、`status` で `succeeded` を引けるため本クエリに有効。`query_id` 単独 index（references 由来）は status 絞り込みに効かないため、複合を追加する。
- **`(query_id, created_at)` 複合 index（不採用）**: 「最新1件」の並び替えは複合 index の末尾に `created_at` を含めれば理論上さらに最適化できるが、最新成功1件は「履歴なし・上書き・最新1件のみ保持」運用（タスク doc）のため、1 query あたりの succeeded 行数はごく少数（実質1件）。`(query_id, status)` で十分に絞り込めるため、`created_at` を含む追加複合 index はカーディナリティに対し過剰と判断し付けない。必要になれば別マイグレーションで追加する。

### あえて今回入れていないもの

- **DB の CHECK 制約（`status` の enum 値・`result_row_count >= 0`）**: アプリ層（enum + バリデーション）で担保する方針（既存テーブルと同様、SQLite + アプリ層担保）。
- **`(query_id)` の一意制約**: 1 query に複数 execution（pending/running 含む履歴的な遷移）が並ぶため一意にしない。最新1件のみ保持は古いレコードの削除（アプリ運用）で実現する。
- **`result_blob` のサイズ制約**: §2 のとおりアプリ層で上限を守るため DB 制約は設けない。

---

## 3. モデル構成（実装段階で作成、本ドキュメントは設計の明記）

マイグレーション承認・実行後の後続実装で、以下を用意する（本ステップでは未作成、参考情報）。

`app/models/query_execution.rb`

```ruby
class QueryExecution < ApplicationRecord
  belongs_to :query
  enum :status, { pending: "pending", running: "running", succeeded: "succeeded", failed: "failed" }
  validates :status, presence: true
  # #store_result / #result（JSON + gzip）等は後続タスクで TDD 実装
end
```

`app/models/query.rb` に `latest_succeeded_execution`（最新成功1件）スコープ/関連を追加（後続タスク）。

---

## 4. 実行するマイグレーションコマンド（承認後に実行）

```bash
bin/rails db:migrate
```

- 影響 DB: development（`storage/development.sqlite3`）、test（`storage/test.sqlite3`）
- 実行後、`db/schema.rb` が `version: 20260531130000` に更新され、`query_executions` テーブル定義が反映される。

テスト DB を schema から再構築する場合:

```bash
bin/rails db:test:prepare
```

---

## 5. ロールバック方法

直前のマイグレーション（この `create_query_executions`）を取り消す:

```bash
bin/rails db:rollback
```

- `change` メソッドで定義しているため、`create_table` は自動的に逆操作（`drop_table`）でロールバックされる（index も併せて削除）。
- ロールバック後は `db/schema.rb` の version が直前（`20260531120000`、`query_parameters` まで）に戻る。

特定バージョンまで戻す場合:

```bash
bin/rails db:migrate:down VERSION=20260531130000
```

---

## 6. 影響範囲

- **development / test**: 新規テーブル追加のみ。既存テーブル（`queries` 等）への変更・データ移行はなし（破壊的変更なし）。`queries` への FK を張るが、`queries` 側の定義は変更しない。
- **production**: 本ステップでは production への適用は行わない。production（`storage/production.sqlite3`、`db/migrate` パス）への反映は別途デプロイ時に検討する（Kamal の運用フローに従う）。
- **既存テスト**: 既存テーブルを変更しないため、既存スペックへの影響はなし。
- **後続実装への依存**: 本マイグレーションは純粋なスキーマ追加で、暗号化キーや外部 API に依存しない。

---

## 7. マイグレーションファイルの内容（転記）

`db/migrate/20260531130000_create_query_executions.rb`

```ruby
class CreateQueryExecutions < ActiveRecord::Migration[8.1]
  def change
    create_table :query_executions do |t|
      t.references :query, null: false, foreign_key: true
      t.string :status, null: false, default: "pending"
      t.text :error_message
      t.binary :result_blob
      t.integer :result_row_count
      t.boolean :result_truncated, default: false
      t.text :result_schema
      t.datetime :started_at
      t.datetime :finished_at

      t.timestamps
    end

    add_index :query_executions, :status
    add_index :query_executions, [ :query_id, :status ]
  end
end
```

---

## 8. 承認をお願いしたい内容・論点

### 承認をお願いしたい内容

- `query_executions` テーブルを新規作成する（破壊的変更なし）
- カラム: `query_id`(references, FK, NOT NULL) / `status`(string, NOT NULL, default `"pending"`) / `error_message`(text, NULL) / `result_blob`(binary, NULL) / `result_row_count`(integer, NULL) / `result_truncated`(boolean, NULL, default `false`) / `result_schema`(text, NULL) / `started_at`(datetime, NULL) / `finished_at`(datetime, NULL) / `created_at` / `updated_at`
- インデックス: `query_id`（references 由来）/ `status`（単独）/ `(query_id, status)`（複合）
- 適用先は development / test の 2 DB のみ（production は別途）

### 論点（司令塔に確認したい点）

1. **`status` の DB default**: `"pending"` を採用（enum 値と一致）。コントローラで `running` を明示作成する設計（タスク doc §グループ4「`QueryExecution(status: running)` 作成」）とも矛盾しない（default は未指定時のフォールバック）。同時実行上限時は `pending` で作成。この default 方針で問題ないか。
2. **`(query_id, created_at)` 複合 index を付けないこと**: 最新成功1件は「上書き・1件のみ保持」運用のため succeeded 行のカーディナリティが極小で、`(query_id, status)` で十分と判断。`created_at` を含む複合 index は付けていない。この判断でよいか。
3. **`result_truncated` を NULL 可（default false）のままにしたこと**: 実行前段階で意味を持たないため NOT NULL までは強制していない。NOT NULL に寄せたい場合は指示があれば変更する。
4. **`result_row_count` の意味（総数 vs 保存行数）**: カラムは用意したが「切り詰め前の総数」「保存した N 行」のどちらを入れるかは後続実装で確定。スキーマには影響しない。

**この内容で `bin/rails db:migrate` を実行してよいか、承認をお願いします（本ステップではマイグレーション準備のみ・未実行）。**
