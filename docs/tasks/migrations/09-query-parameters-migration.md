# マイグレーション確認用ドキュメント: `query_parameters` テーブル作成

> トピック **09-parameterized-query**（パラメータ化クエリ）の最初の作業。`{{ name }}` 記法で抽出したパラメータ定義を永続化する `QueryParameter` モデルのテーブルを新規作成する。
> **このドキュメントの承認後に `bin/rails db:migrate` を実行する。承認前は実行しない。**

- **対象マイグレーション**: `db/migrate/20260531120000_create_query_parameters.rb`（クラス名 `CreateQueryParameters`）
- **テーブル名**: `query_parameters` / **モデル名**: `QueryParameter`（フラットなトップレベル、`Query` 配下の関連）
- **作成日**: 2026-05-31
- **担当**: Coder
- **ステータス**: ✅承認済み（ボス確定スキーマ・migrate 実行許可済み）

> **構成に関する司令塔/ボス確定方針（2026-05-31）**:
> - `QueryParameter` は **フラットなトップレベル**（ネームスペースなし）。テーブルは `query_parameters`。
> - `Query has_many :query_parameters, dependent: :destroy` / `QueryParameter belongs_to :query` の関連。
> - 型は `%i[string number date date_range]`。DB には `param_type`（string）に文字列で保存する。
> - **`position` カラムなし**（表示順は SQL 内の出現順 = レコード `id` 順 = 作成順で代替するため不要）。
> - **`required` カラムなし**（per-param の必須フラグは持たない。**全パラメータを必須として扱う**運用に確定）。

---

## 1. 追加するテーブル・カラム・制約・インデックス

### テーブル: `query_parameters`（新規作成）

| カラム名 | 型 | NULL | デフォルト | 制約・備考 |
|----------|------|:----:|------------|-----------|
| `id` | integer (PK) | NOT NULL | 自動採番 | Rails 標準の主キー（自動付与）。出現順 = 作成順 = `id` 順 |
| `query_id` | integer (FK) | NOT NULL | なし | `queries.id` への外部キー。`t.references :query, foreign_key: true` で FK 制約 + index を付与 |
| `name` | string | NOT NULL | なし | パラメータ名（例: `user_id`）。`{{ name }}` から抽出した識別子。英数字/アンダースコアのみの検証はモデル層で実施 |
| `param_type` | string | NOT NULL | なし | パラメータ型。`%i[string number date date_range]` のいずれかを文字列で保存（後述の理由参照） |
| `created_at` | datetime | NOT NULL | なし | `t.timestamps` により自動付与 |
| `updated_at` | datetime | NOT NULL | なし | `t.timestamps` により自動付与 |

### インデックス

| インデックス名 | 対象カラム | 種別 | 目的 |
|----------------|-----------|------|------|
| `index_query_parameters_on_query_id` | `query_id` | 通常 | `t.references` により自動付与。`query.query_parameters` 取得・FK 整合性のため |
| `index_query_parameters_on_query_id_and_name` | `(query_id, name)` | **unique** | 同一クエリ内のパラメータ名重複防止 + `sync_parameters!` の upsert キー（§2 参照） |

---

## 2. 各カラム・制約の目的・設計判断

- **`query_id`（references / FK / NOT NULL / index）**
  パラメータは必ず 1 つの `Query` に従属する子レコードであり、親なしのパラメータは無意味なため NOT NULL。`foreign_key: true` で参照整合性を DB レベルで担保し、`Query` 側は `dependent: :destroy` で削除時に追従する。`t.references` が `query_id` への index を自動付与する。

- **`name`（string / NOT NULL）**
  `{{ user_id }}` 記法から抽出するパラメータ識別子。`@name` へのバインド名・実行フォームのフィールド名に使う。空のパラメータ名は無意味なので NOT NULL。フォーマット検証（英数字/アンダースコアのみ）はモデル層（`format` 検証）で実施し、DB の CHECK 制約は付けない（`users` / `bigquery_connections` と同様、アプリ層担保の方針）。

- **`param_type`（string / NOT NULL）**
  パラメータの型。`%i[string number date date_range]` のいずれか。
  - **string で持つ理由**: 取り得る値が少数の固定集合（4 種）であり、`enum`（integer）化すると DB に格納される整数値が意味を持たず、SQL を直接見たときに型が読めない。BigQuery バインドへの型マッピングは Ruby 側で行うため、DB は人間可読な文字列で保持する方が運用・デバッグ時に分かりやすい。妥当性（4 種内）はモデルの `inclusion` 検証で担保（DB CHECK 制約は付けない＝既存方針に揃える）。
  - **NOT NULL の理由**: 型のないパラメータは BigQuery バインドできず無意味なため必須。

- **`created_at` / `updated_at`**
  `t.timestamps` による標準のタイムスタンプ。表示順（= `id` 順 = 作成順 = SQL 出現順）の安定化にも `id`/作成順を用いるため、別途 `position` カラムは設けない。

### `(query_id, name)` 複合 unique index — **付与する**

- **同名重複防止**: 同一クエリ内で同じパラメータ名が 2 つ存在しても、`@name` バインドは 1 つの値しか持てないため意味的に重複は許されない。DB レベルで一意性を保証する。
- **`sync_parameters!` の upsert キー**: `query.update(sql: ...)` 時に `sync_parameters!` がパラメータを「追加・削除・更新」する。`(query_id, name)` を一意キーとすることで、`find_or_initialize_by(name:)` ベースの突き合わせ（同名は更新、消えた名前は削除、新規名は作成）を安全に行え、競合（重複行）を構造的に排除できる。
- **同名重複パース仕様との整合**: `{{ x }}` が SQL 内に複数回出現するケースは、パース時に名前で集約して **1 レコードに正規化**する前提。これと unique index は整合する。

### あえて持たないカラム
- **`position`**: 表示順は SQL 出現順（= 作成順 = `id` 順、`order(:id)`）で代替できるため不要。
- **`required`**: per-param の必須/任意フラグは持たない。**全パラメータを必須**として扱う（実行フォームは全フィールド HTML5 `required`、サーバ側でも未入力が 1 つでもあれば実行拒否）。フラグ用カラムは設けない。

---

## 3. モデル構成（実装段階で作成）

`app/models/query_parameter.rb`

```ruby
class QueryParameter < ApplicationRecord
  SUPPORTED_TYPES = %i[string number date date_range].freeze

  belongs_to :query

  validates :name, presence: true, format: { with: /\A\w+\z/ }
  validates :param_type, presence: true, inclusion: { in: SUPPORTED_TYPES.map(&:to_s) }
  # #to_bigquery_param 等は後続タスクで実装
end
```

`app/models/query.rb`（追記分）

```ruby
has_many :query_parameters, dependent: :destroy
# parameters / bound_sql / sync_parameters! / permit_parameter_values / missing_parameter_values は後続タスクで TDD 実装
```

---

## 4. 実行するマイグレーションコマンド（承認後に実行）

```bash
bin/rails db:migrate
bin/rails db:test:prepare
```

- 影響 DB: development（`storage/development.sqlite3`）、test（`storage/test.sqlite3`）
- 実行後、`db/schema.rb` が `version: 20260531120000` に更新され、`query_parameters` テーブル定義が反映される。

---

## 5. ロールバック方法

```bash
bin/rails db:rollback
```

- `change` メソッド定義のため、`create_table` / `add_index` は自動的に逆操作（`drop_table`）でロールバックされる。
- ロールバック後は `db/schema.rb` の version が直前（`20260531110000`、`application_settings` まで）に戻る。

特定バージョンまで戻す場合:

```bash
bin/rails db:migrate:down VERSION=20260531120000
```

---

## 6. 影響範囲

- **development / test**: 新規テーブル追加のみ。既存テーブル（`users` / `bigquery_connections` / `queries` / `application_settings`）への変更・データ移行はなし（破壊的変更なし）。
- **production**: 本ステップでは適用しない（別途デプロイ時に Kamal フローで検討）。
- **既存テスト**: 既存テーブルを変更しないため、既存スペックへの影響はなし。

---

## 7. マイグレーションファイルの内容（転記）

`db/migrate/20260531120000_create_query_parameters.rb`

```ruby
class CreateQueryParameters < ActiveRecord::Migration[8.1]
  def change
    create_table :query_parameters do |t|
      t.references :query, null: false, foreign_key: true
      t.string :name, null: false
      t.string :param_type, null: false

      t.timestamps
    end

    add_index :query_parameters, [ :query_id, :name ], unique: true
  end
end
```

---

## 8. 承認内容（確定）

- `query_parameters` テーブルを新規作成する（破壊的変更なし）
- カラム: `query_id`(references, FK, NOT NULL, index) / `name`(string, NOT NULL) / `param_type`(string, NOT NULL) / `created_at` / `updated_at`
- インデックス: `query_id`（references 自動付与）+ `(query_id, name)` の **複合 unique index**
- **`position` なし・`required` なし**（全パラメータ必須として扱う）
- 適用先は development / test の 2 DB のみ（production は別途）

**ボス確定スキーマ・migrate 実行許可済み。**
