# マイグレーション確認用ドキュメント: `queries` テーブル作成

> トピック **07-query-editor**（クエリエディタ・Query モデル）の最初の作業。`Query` モデルのテーブルを新規作成する。
> **このドキュメントの承認後に `bin/rails db:migrate` を実行する。承認前は実行しない。**

- **対象マイグレーション**: `db/migrate/20260531100000_create_queries.rb`（クラス名 `CreateQueries`）
- **テーブル名**: `queries` / **モデル名**: `Query`（**フラットなトップレベル**、ネームスペースなし）
- **作成日**: 2026-05-31
- **担当**: Coder
- **ステータス**: ✅承認済み（改訂版・接続必須）→ migrate 実行可

> **改訂（2026-05-31, ボス決定）**: `bigquery_connection_id` を **NOT NULL（接続必須）** に変更。当初案の nullable（下書きは接続未選択可）を撤回し、**下書きでも接続選択を要求する方針**とする。アソシエーションも `belongs_to :bigquery_connection, class_name: "Bigquery::Connection"`（`optional: true` を撤回）。この修正適用＝改訂版マイグレーションの承認とみなす。

> **命名に関する司令塔確定方針（2026-05-31）**:
> - `Query` モデルは **フラットなトップレベル**（ネームスペースなし）。テーブルは `queries`（`Query` の標準複数形）。
> - 接続への FK は **`bigquery_connection_id`**（`t.references :bigquery_connection, foreign_key: true, null: false`）。参照先テーブルは既存の `bigquery_connections`（モデル `Bigquery::Connection`）。
> - `user_id` は `t.references :user, foreign_key: true, null: false`。
> - アソシエーション（実装段階の参考）: `belongs_to :user` / `belongs_to :bigquery_connection, class_name: "Bigquery::Connection"`（**接続必須**）。
>
> 注: タスク仕様書 `07-query-editor.md` §2 では FK 名が `connection_id` と記載されているが、**司令塔の確定方針（`bigquery_connection_id`）を優先**する。理由は §2 を参照。

---

## 1. 追加するテーブル・カラム・制約・インデックス

### テーブル: `queries`（新規作成）

`Query` モデル（フラット）が標準の複数形テーブル `queries` にマップされる。

| カラム名 | 型 | NULL | デフォルト | 制約・備考 |
|----------|------|:----:|------------|-----------|
| `id` | integer (PK) | NOT NULL | 自動採番 | Rails 標準の主キー（自動付与） |
| `title` | string | NOT NULL | なし | クエリの表示名。一覧・タイトル検索（§4.11）で使用。必須（モデルでも `presence` 検証） |
| `sql_body` | text | NOT NULL | なし | SQL 本文。長文になり得るため `text`。必須（モデルでも `presence` 検証） |
| `user_id` | integer (FK) | NOT NULL | なし | 所有ユーザー。`users.id` への FK。`t.references` により index 自動付与 |
| `bigquery_connection_id` | integer (FK) | **NOT NULL** | なし | 実行対象の BigQuery 接続。`bigquery_connections.id` への FK。`t.references` により index 自動付与。**接続必須（ボス決定）** |
| `created_at` | datetime | NOT NULL | なし | `t.timestamps` により自動付与 |
| `updated_at` | datetime | NOT NULL | なし | `t.timestamps` により自動付与。一覧の更新日時降順ソート（§4.11）に使用 |

### インデックス

| インデックス名 | 対象カラム | 種別 | 目的 |
|----------------|-----------|------|------|
| `index_queries_on_user_id` | `user_id` | 通常 | `t.references :user` が自動付与。所有ユーザーでの絞り込み・FK 整合 |
| `index_queries_on_bigquery_connection_id` | `bigquery_connection_id` | 通常 | `t.references :bigquery_connection` が自動付与。接続での絞り込み・FK 整合 |
| （`title` への index は付けない） | `title` | — | 要否は §2「title index の要否」を参照（**今回は付けない**） |

---

## 2. 各カラムの目的・設計判断

- **`title`（string / NOT NULL）**
  クエリを人間が識別するための表示名。一覧画面・タイトル部分一致検索（§4.11）で使用する。必須（モデルで `presence` 検証）。

- **`sql_body`（text / NOT NULL）**
  SQL 本文。CodeMirror エディタで編集する内容を保存する。
  - **型を `text` にした理由**: SQL 本文は `string`（可変長だが運用上短文向き）の想定を超える長文になり得るため、長文を素直に扱える `text` を採用。
  - **NOT NULL の理由**: 「SQL のないクエリ」は業務上無意味。空クエリの保存を防ぐため DB 制約として NOT NULL を採用し、実質必須はモデルの `presence` 検証で担保する。

- **`user_id`（integer FK / NOT NULL）**
  クエリの所有ユーザー。`t.references :user, null: false, foreign_key: true` で定義。
  - **NOT NULL の理由（司令塔確定方針）**: クエリは必ず所有者を持つ。所有者のないクエリは存在し得ないため DB 制約で NOT NULL を強制する。FK 制約により、存在しない user を参照できない・参照中の user を不用意に削除できない（整合性担保）。
  - index は `t.references` が自動付与（所有ユーザーでの一覧絞り込みに有効）。

- **`bigquery_connection_id`（integer FK / NOT NULL）**
  クエリを実行する対象の BigQuery 接続。`t.references :bigquery_connection, null: false, foreign_key: true` で定義。参照先は既存テーブル `bigquery_connections`（モデル `Bigquery::Connection`）。
  - **FK 名を `bigquery_connection_id` にした理由（司令塔確定方針）**: 既存テーブル名が `bigquery_connections` で、モデルがネームスペース方式の `Bigquery::Connection`。`t.references :bigquery_connection` とすることで Rails の規約どおり `bigquery_connection_id` カラム・`bigquery_connections` テーブルへの FK・対応 index が一貫して生成される。`connection_id` という汎用名（タスク仕様書の旧記載）よりも、参照先が BigQuery 接続であることが名前から明確で、既存テーブル命名（ネームスペース方式）とも整合する。
  - **NOT NULL（接続必須）の理由（ボス決定・2026-05-31）**: 当初は「下書きは接続未選択可」として nullable を提案したが、ボス決定により **接続必須・下書きでも接続選択を要求する方針** に変更。クエリは最終的に必ず特定の BigQuery 接続上で実行されるドメイン概念であり、接続未確定のクエリを許すとエディタ/実行（トピック10）の前提が曖昧になる。よって DB 制約で NOT NULL を強制し、接続のないクエリを作れないようにする。実装側は `belongs_to :bigquery_connection, class_name: "Bigquery::Connection"`（`optional: true` なし）とする。
  - UI 上は、接続が 1 件ならデフォルト選択、0 件なら接続登録へ誘導する（接続選択を必ず伴う）。
  - index は `t.references` が自動付与（接続での絞り込み・FK 整合に有効）。

- **`created_at` / `updated_at`**
  `t.timestamps` による標準のタイムスタンプ。`updated_at` は一覧の更新日時降順ソート（§4.11 / タスク §3）に使用する。

### `title` index の要否（検討結果: 今回は付けない）

タスク §3 / 計画書 §4.11 では「タイトル部分一致検索」（`?q=foo` → `title LIKE '%foo%'`）が要件。これを踏まえ `title` への index 要否を検討した。

- **結論: 今回は付けない。**
- **理由**:
  1. §4.11 は明示的に「**最小**」「タイトル部分一致検索のみ」「全文検索は将来（§7）」と決定されている。検索は前方一致ではなく**両端ワイルドカードの `LIKE '%...%'`** であり、SQLite の B-tree index は両端ワイルドカードの部分一致では効かない（前方一致 `'foo%'` でしか効かない）。よって通常の `title` index を付けても今回の検索パターンには寄与しない。
  2. 想定データ規模が小さい（単一組織セルフホスト、クエリ件数は数百〜数千オーダー想定）。全件スキャン相当でも実用上の性能問題は生じにくい。
  3. 将来、本格的な検索性能が必要になった場合は FTS5（SQLite 全文検索）や別 index を**別マイグレーション**で追加する方が、要件（§7「全文検索は将来」）と整合する。
- **付ける場合の選択肢（将来）**: 前方一致検索に切り替えるなら通常 index、部分一致を高速化するなら FTS5 仮想テーブル。いずれも将来要件確定後に別マイグレーションで対応する。

### あえて今回入れていないもの
- **`title` への index**: 上記のとおり、両端ワイルドカード部分一致では効かず、規模も小さいため不要（将来 FTS5 等で対応）。
- **`(user_id, updated_at)` 複合 index**: 一覧の「更新日時降順」ソートは現状規模では不要。必要になれば別マイグレーションで追加。
- **`title` の一意制約**: 同一ユーザーが同名クエリを複数持つことを禁じる要件はないため付けない。
- **DB の CHECK 制約**: 値検証はアプリ層（モデルの `presence` 等）で担保する方針（`users` / `bigquery_connections` と同様）。

---

## 3. モデル構成（実装段階で作成、本ドキュメントは設計の明記）

マイグレーション承認・実行後の実装で、以下を用意する（本ステップでは未作成、参考情報）。

`app/models/query.rb`（モデル本体。バリデーション・アソシエーションは後続タスクで TDD 実装）

```ruby
class Query < ApplicationRecord
  belongs_to :user
  belongs_to :bigquery_connection, class_name: "Bigquery::Connection"

  # validates :title, presence: true
  # validates :sql_body, presence: true
end
```

- `Query` はフラット（ネームスペースなし）なので標準どおり `queries` テーブルにマップされる（`Query.table_name # => "queries"`）。
- `bigquery_connection` は既存の `Bigquery::Connection` を `class_name` 指定で参照する（**接続必須**、`optional` なし）。

---

## 4. 実行するマイグレーションコマンド（承認後に実行）

```bash
bin/rails db:migrate
```

- 影響 DB: development（`storage/development.sqlite3`）、test（`storage/test.sqlite3`）
- 実行後、`db/schema.rb` が `version: 20260531100000` に更新され、`queries` テーブル定義が反映される。

テスト DB を schema から再構築する場合:

```bash
bin/rails db:test:prepare
```

---

## 5. ロールバック方法

直前のマイグレーション（この `create_queries`）を取り消す:

```bash
bin/rails db:rollback
```

- `change` メソッドで定義しているため、`create_table` は自動的に逆操作（`drop_table`）でロールバックされる。
- ロールバック後は `db/schema.rb` の version が直前（`20260531092141`、`bigquery_connections` まで）に戻る。

特定バージョンまで戻す場合:

```bash
bin/rails db:migrate:down VERSION=20260531100000
```

---

## 6. 影響範囲

- **development / test**: 新規テーブル追加のみ。既存テーブル（`users` / `bigquery_connections`）への変更・データ移行はなし（破壊的変更なし）。
- **FK 依存**: `queries.user_id` → `users.id`、`queries.bigquery_connection_id` → `bigquery_connections.id` の 2 つの FK を追加する。両参照先テーブルは既存（適用済み前提）。`bigquery_connections` 未適用の環境では先に 04 のマイグレーションが適用されている必要がある（タイムスタンプ順で 04 → 07 の順に適用されるため通常問題なし）。
- **production**: 本ステップでは production への適用は行わない。production（`storage/production.sqlite3`、`db/migrate` パス）への反映は別途デプロイ時に検討する（Kamal の運用フローに従う）。
- **既存テスト**: 既存テーブルを変更しないため、既存スペックへの影響はなし。

---

## 7. マイグレーションファイルの内容（転記）

`db/migrate/20260531100000_create_queries.rb`

```ruby
class CreateQueries < ActiveRecord::Migration[8.1]
  def change
    create_table :queries do |t|
      t.string :title, null: false
      t.text :sql_body, null: false
      t.references :user, null: false, foreign_key: true
      t.references :bigquery_connection, null: false, foreign_key: true

      t.timestamps
    end
  end
end
```

---

## 8. 承認をお願いしたい内容・論点

### 承認内容（✅承認済み・改訂版）
- `queries` テーブルを新規作成する（破壊的変更なし）
- カラム: `title`(string, NOT NULL) / `sql_body`(text, NOT NULL) / `user_id`(integer, FK→users, NOT NULL, index) / `bigquery_connection_id`(integer, FK→bigquery_connections, **NOT NULL**, index) / `created_at` / `updated_at`
- index は `t.references` 由来の `user_id` / `bigquery_connection_id` の 2 つのみ。**`title` への index は付けない**（理由 §2）
- 適用先は development / test の 2 DB のみ（production は別途）

### 論点（解決済み）
1. **FK 名 `bigquery_connection_id`（司令塔確定方針）の採用** → ✅ **承認**。タスク仕様書 §2 の旧記載 `connection_id` ではなく、司令塔の確定方針どおり `bigquery_connection_id` を採用。
2. **`bigquery_connection_id` の NULL 可否** → ✅ **解決（ボス決定・2026-05-31）**: 当初案の NULL 可（optional）を撤回し、**NOT NULL（接続必須）** に変更。下書きでも接続選択を要求する方針。アソシエーションも `optional` を撤回。
3. **`title` index を付けないこと** → ✅ **承認**。§4.11 が「最小・両端ワイルドカード部分一致のみ・全文検索は将来」のため、通常 index は効かず規模も小さいので付けない（将来 FTS5 等で別マイグレーション対応）。

**この改訂版（接続必須）で `bin/rails db:migrate` 実行が承認済み。**
