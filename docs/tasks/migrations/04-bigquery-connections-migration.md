# マイグレーション確認用ドキュメント: `bigquery_connections` テーブル作成

> トピック **04-bigquery-connection**（BigQuery接続・Connectionモデル）の最初の作業。`Bigquery::Connection` モデルのテーブルを新規作成する。
> **このドキュメントの承認後に `bin/rails db:migrate` を実行する。承認前は実行しない。**

- **対象マイグレーション**: `db/migrate/20260531092141_create_bigquery_connections.rb`（クラス名 `CreateBigqueryConnections`）
- **テーブル名**: `bigquery_connections` / **モデル名**: `Bigquery::Connection`（ネームスペース方式）
- **作成日**: 2026-05-31
- **担当**: Coder
- **ステータス**: 承認待ち（未実行）

> **命名に関する司令塔/ボス決定（2026-05-31）**: テーブル名 `connections` は汎用的すぎるため、BigQuery 接続であることが分かるよう **ネームスペース方式**に統一する。
> - モデル: **`Bigquery::Connection`**（ファイル `app/models/bigquery/connection.rb`）
> - ネームスペースのテーブルプレフィックス: `app/models/bigquery.rb` に `table_name_prefix` を定義し、`Bigquery::Connection` がテーブル `bigquery_connections` にマップされるようにする。
> - テーブル名: **`bigquery_connections`**（`create_table :bigquery_connections` / クラス名 `CreateBigqueryConnections`）
> - コントローラ: `Bigquery::ConnectionsController`（`app/controllers/bigquery/connections_controller.rb`）、ルーティング: `namespace :bigquery do resources :connections end`（パスは `/bigquery/connections`）。実装段階で対応。
> - クライアント返却メソッドは受け入れ条件どおり `#bigquery`（`bigquery_connection.bigquery` が `Google::Cloud::Bigquery` を返す）。

---

## 1. 追加するテーブル・カラム・制約・インデックス

### テーブル: `bigquery_connections`（新規作成）

`Bigquery::Connection` モデルが、`Bigquery` モジュールの `table_name_prefix`（`"bigquery_"`）+ モデル名複数形（`connections`）= `bigquery_connections` にマップされる。

| カラム名 | 型 | NULL | デフォルト | 制約・備考 |
|----------|------|:----:|------------|-----------|
| `id` | integer (PK) | NOT NULL | 自動採番 | Rails 標準の主キー（自動付与） |
| `name` | string | NOT NULL | なし | 接続の表示名（例: 「本番」） |
| `project_id` | string | NOT NULL | なし | GCP プロジェクト ID。フォーマット検証（英数字/ハイフン）はモデル層で実施 |
| `service_account_json` | text | NOT NULL | なし | SA JSON 鍵。**Active Record Encryption で暗号化したバイト列を格納**。平文は保存しない |
| `maximum_bytes_billed` | bigint | NULL 可 | なし | クエリのコスト上限（バイト）。NULL = 上限なし |
| `created_at` | datetime | NOT NULL | なし | `t.timestamps` により自動付与 |
| `updated_at` | datetime | NOT NULL | なし | `t.timestamps` により自動付与 |

### インデックス

| インデックス名 | 対象カラム | 種別 | 目的 |
|----------------|-----------|------|------|
| （なし） | — | — | 本テーブルには追加インデックスを付けない（理由は §2 参照） |

---

## 2. 各カラムの目的・設計判断

- **`name`（string / NOT NULL）**
  接続を人間が識別するための表示名。一覧画面・選択 UI で使用する。必須（モデルでも `presence` 検証）。

- **`project_id`（string / NOT NULL）**
  BigQuery クライアント生成時に渡す GCP プロジェクト ID。`Bigquery::Connection#bigquery` で必須のため NOT NULL。
  値のフォーマット（英数字/ハイフン）はアプリ層（モデルの `format` 検証）で担保し、DB の CHECK 制約は付けない（SQLite + アプリ層担保の方針、`users` テーブルと同様）。

- **`service_account_json`（text / NOT NULL）**
  SA JSON 鍵を **Active Record Encryption（`encrypts :service_account_json`）で暗号化**して保存する。DB に書かれるのは暗号文（Base64/IV/タグ等を含む構造）であり、平文 JSON は保存されない。
  - **型を `text` にした理由**: 暗号化後の値は元の JSON より長くなり（IV・認証タグ・メタデータが付与される）、`text` が意味的に適切。元の SA JSON 自体も数 KB になり得る。
  - **NOT NULL にした理由（司令塔/ボス承認済み）**: `Bigquery::Connection#bigquery` が SA JSON を必須とするため、業務上「SA JSON のない接続」は無意味。**DB 制約として NOT NULL を採用**する。
    - 補足: Active Record Encryption は `nil` を暗号化せず素通しするため、DB NOT NULL は「nil 防止の安全網」と位置づけ、実質必須はモデルの `presence` + JSON パース検証で担保する。
    - 編集フォームで「変更しない場合は空欄」を許す UI 要件（タスク §未決事項）は、**コントローラ側で空欄なら既存値を保持する**ことで対応し、DB に空文字や NULL を書かない運用とする。DB の NOT NULL とは矛盾しない。

- **`maximum_bytes_billed`（bigint / NULL 可）**
  BigQuery のクエリ単位コスト上限（バイト数）。
  - **`bigint` の理由**: バイト単位の上限は容易に 32bit（約 21.4 億 ≒ 約 2GB）を超える（例: 10GB = 10_000_000_000）。`integer`（4byte）では桁あふれするため `bigint`（8byte）が必須。
  - **NULL 可の理由**: BigQuery の `maximum_bytes_billed` は「未設定 = 上限なし」が自然なセマンティクス。NULL を「上限なし」として表現する。`0` を「上限なし」に流用すると BigQuery 側の意味（0 バイトで即失敗）と衝突するため、NULL と数値を明確に分ける。値が入る場合は 1 以上（モデルで `numericality: { greater_than: 0 }, allow_nil: true` を検証）。

- **`created_at` / `updated_at`**
  `t.timestamps` による標準のタイムスタンプ。監査・並び替えに使用。

### あえて今回入れていないもの
- **`project_id` / `name` への一意インデックス**: 計画書では「複数 Connection を持てる構造（初期運用は 1 接続）」とされ、同一プロジェクトに対し用途別の複数接続を許容し得るため、現時点で一意制約は付けない。必要になれば別マイグレーションで追加する。
- **`service_account_json` 用の検索インデックス**: 暗号化カラムであり検索キーにしないため不要。
- **DB の CHECK 制約（`project_id` 形式・`maximum_bytes_billed > 0`）**: アプリ層（モデル検証）で担保する方針（`users` と同様）。

---

## 3. モデル/ネームスペース構成（実装段階で作成、本ドキュメントは設計の明記）

マイグレーション承認・実行後の実装で、以下のファイルを用意する（本ステップでは未作成、参考情報）。

`app/models/bigquery.rb`（ネームスペースのテーブルプレフィックス定義）

```ruby
module Bigquery
  def self.table_name_prefix
    "bigquery_"
  end
end
```

`app/models/bigquery/connection.rb`（モデル本体。バリデーション・`encrypts`・`#bigquery` は後続タスクで TDD 実装）

```ruby
class Bigquery::Connection < ApplicationRecord
  # encrypts :service_account_json
  # validations / #bigquery は後続タスクで実装
end
```

これにより `Bigquery::Connection.table_name # => "bigquery_connections"` となり、マイグレーションで作る `bigquery_connections` テーブルに正しくマップされる。

---

## 4. 実行するマイグレーションコマンド（承認後に実行）

```bash
bin/rails db:migrate
```

- 影響 DB: development（`storage/development.sqlite3`）、test（`storage/test.sqlite3`）
- 実行後、`db/schema.rb` が `version: 20260531092141` に更新され、`bigquery_connections` テーブル定義が反映される。

テスト DB を schema から再構築する場合:

```bash
bin/rails db:test:prepare
```

---

## 5. ロールバック方法

直前のマイグレーション（この `create_bigquery_connections`）を取り消す:

```bash
bin/rails db:rollback
```

- `change` メソッドで定義しているため、`create_table` は自動的に逆操作（`drop_table`）でロールバックされる。
- ロールバック後は `db/schema.rb` の version が直前（`20260531000928`、`users` のみ）に戻る。

特定バージョンまで戻す場合:

```bash
bin/rails db:migrate:down VERSION=20260531092141
```

---

## 6. 影響範囲

- **development / test**: 新規テーブル追加のみ。既存テーブル（`users`）への変更・データ移行はなし（破壊的変更なし）。
- **production**: 本ステップでは production への適用は行わない。production（`storage/production.sqlite3`、`db/migrate` パス）への反映は別途デプロイ時に検討する（Kamal の運用フローに従う）。
- **既存テスト**: 既存テーブルを変更しないため、既存スペックへの影響はなし。
- **暗号化キー依存**: `service_account_json` の暗号化（`encrypts`）はトピック 01 で設定済みの Active Record Encryption キーを使う（§8 参照）。**マイグレーション（テーブル作成）自体はキー設定に依存しない。**

---

## 7. マイグレーションファイルの内容（転記）

`db/migrate/20260531092141_create_bigquery_connections.rb`

```ruby
class CreateBigqueryConnections < ActiveRecord::Migration[8.1]
  def change
    create_table :bigquery_connections do |t|
      t.string :name, null: false
      t.string :project_id, null: false
      t.text :service_account_json, null: false
      t.bigint :maximum_bytes_billed

      t.timestamps
    end
  end
end
```

---

## 8. 承認をお願いしたい内容・論点（解決済みの反映）

### 承認をお願いしたい内容
- `bigquery_connections` テーブルを新規作成する（破壊的変更なし）
- カラム: `name`(string, NOT NULL) / `project_id`(string, NOT NULL) / `service_account_json`(text, NOT NULL, AR Encryption で暗号化) / `maximum_bytes_billed`(bigint, NULL 可) / `created_at` / `updated_at`
- 追加インデックスなし
- 適用先は development / test の 2 DB のみ（production は別途）

### 論点（解決済み）
1. **`service_account_json` の NOT NULL 可否** → ✅ **解決（2026-05-31, 司令塔/ボス承認）**: NOT NULL を採用。AR Encryption は `nil` を素通しするため DB NOT NULL は「nil 防止の安全網」、実質必須はモデルの `presence` + JSON 検証で担保。「変更しない場合は空欄」UI はコントローラで既存値保持して対応。
2. **Active Record Encryption のキー設定** → ✅ **解決（2026-05-31, 司令塔検証済み）**: トピック 01 で設定済み（`bin/rails runner "puts ActiveRecord::Encryption.config.primary_key"` がキーを返す＝credentials に保存され Rails 8 が自動ロード）。本トピックでのキー設定は不要。後続の `encrypts :service_account_json` はそのまま機能する。
3. **テーブル/モデル命名** → ✅ **決定（2026-05-31, 司令塔/ボス）**: **ネームスペース方式**。モデル `Bigquery::Connection`（`app/models/bigquery/connection.rb`）、`app/models/bigquery.rb` の `table_name_prefix "bigquery_"` でテーブル `bigquery_connections` にマップ。コントローラ `Bigquery::ConnectionsController`、ルーティング `namespace :bigquery do resources :connections end`（`/bigquery/connections`）。クライアント返却メソッドは `#bigquery`。

**この内容で `bin/rails db:migrate` を実行してよいか、承認をお願いします。**
