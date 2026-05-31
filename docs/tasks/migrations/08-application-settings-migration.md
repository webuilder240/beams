# マイグレーション確認用ドキュメント: `application_settings` テーブル作成

> トピック **08-cost-protection**（コスト保護・dry-run／上限ガード）グループ2「単価設定（ApplicationSetting）」の最初の作業。GB→円換算の単価を保持するシングルトン設定テーブル `application_settings` を新規作成する。
> **このドキュメントの承認後に `bin/rails db:migrate` を実行する。承認前は実行しない。**

- **対象マイグレーション**: `db/migrate/20260531110000_create_application_settings.rb`（クラス名 `CreateApplicationSettings`）
- **テーブル名**: `application_settings` / **モデル名**: `ApplicationSetting`（トップレベル・名前空間なし）
- **作成日**: 2026-05-31
- **担当**: Coder
- **ステータス**: 承認待ち（未実行）

> **設計に関する司令塔確定方針（2026-05-31）**:
> - `ApplicationSetting` は**フラットなトップレベルのシングルトン設定モデル**（将来は他の設定値も保持し得る汎用設定の置き場）。テーブル名は `application_settings`。
> - GB→円換算レートは **グローバル 1 設定**（Connection 単位ではない）。カラム `bigquery_yen_per_tb`（decimal, NOT NULL, デフォルト 950.0）。
> - シングルトン運用（行は常に 1 つ）。シングルトン担保は**モデル側**（例: `ApplicationSetting.instance` で 1 行を取得/生成）で行う。**マイグレーション自体は通常のテーブル作成のみ**で、DB 制約での 1 行強制はしない。

---

## 1. 追加するテーブル・カラム・制約・インデックス

### テーブル: `application_settings`（新規作成）

| カラム名 | 型 | NULL | デフォルト | 制約・備考 |
|----------|------|:----:|------------|-----------|
| `id` | integer (PK) | NOT NULL | 自動採番 | Rails 標準の主キー（自動付与） |
| `bigquery_yen_per_tb` | decimal(10, 2) | NOT NULL | `950.0` | BigQuery スキャン 1TB あたりの円単価。コスト換算（GB×単価）の基準値 |
| `created_at` | datetime | NOT NULL | なし | `t.timestamps` により自動付与 |
| `updated_at` | datetime | NOT NULL | なし | `t.timestamps` により自動付与 |

### インデックス

| インデックス名 | 対象カラム | 種別 | 目的 |
|----------------|-----------|------|------|
| （なし） | — | — | シングルトン（1 行）運用のため検索用インデックスは不要（理由は §2 参照） |

---

## 2. 各カラムの目的・設計判断

- **`bigquery_yen_per_tb`（decimal(10, 2) / NOT NULL / default 950.0）**
  BigQuery オンデマンドのスキャン課金（1TB あたり）を**円**で表した単価。`CostEstimate`（後続実装の PORO）が GB×単価で推定円コストを算出する際の基準値。

  - **なぜ `decimal`（`float` でない）か**:
    金額・単価は**正確な十進小数**で扱う必要がある。`float`（IEEE 754 二進浮動小数点）では `950.0` のような値や乗算結果に丸め誤差が生じ、円換算表示が不正確になり得る。`decimal` は十進で正確に保持できるため、金額単価には `decimal` を採用する。

  - **なぜ `precision: 10, scale: 2` か**:
    - `scale: 2` … 円単価として「銭」相当の小数第 2 位まで保持できれば実用上十分（例: 950.00、6.25 USD 由来の端数調整も収まる）。
    - `precision: 10` … 整数部は 10 − 2 = 8 桁まで表現可能（最大 99,999,999.99）。1TB あたりの円単価が 8 桁（数千万円）に達することは現実的にあり得ず、十分な余裕を持つ妥当な上限。過大な精度を避けつつ将来のレート変動・桁上がりにも耐える値として設定した。

  - **なぜ NOT NULL か**:
    換算には単価が必ず必要であり、「単価未設定（NULL）」という状態は業務上意味を持たない。NULL を排除し、常に有効な値が入ることを DB 制約として担保する。

  - **なぜデフォルト 950.0 か（根拠）**:
    BigQuery オンデマンド料金は **$6.25/TB**（2024 年時点）。これを円換算すると概ね **¥950/TB**（$6.25 × 約 152 円/$ ≒ ¥950）。初期値として妥当なグローバル単価であり、admin 画面から後から上書き可能とする。デフォルトを置くことで、マイグレーション直後やシングルトン初期生成時に有効な換算が即座に行える。

  - **なぜグローバル 1 設定（Connection 単位でない）か**:
    換算レート（円/TB）は BigQuery の料金体系に紐づく値であり、接続先ごとに変わる性質のものではない。複数 Connection があっても適用すべき単価は同一であるため、グローバルに 1 つ持つのが自然で重複・不整合を避けられる。Connection 固有のコスト制御（上限）は別カラム `bigquery_connections.maximum_bytes_billed` が担う（責務分離）。

- **`created_at` / `updated_at`**
  `t.timestamps` による標準のタイムスタンプ。単価変更の監査（いつ更新されたか）に使用する。

### シングルトン（1 行）の担保方法

- **DB 制約では 1 行を強制しない**。マイグレーションは通常の `create_table` のみ。
- シングルトンは**モデル側**で担保する想定（実装は後続タスク・本ステップでは未作成）。例:

  ```ruby
  class ApplicationSetting < ApplicationRecord
    def self.instance
      first_or_create!
    end
  end
  ```

  `ApplicationSetting.instance` が常に最初の 1 行を取得し、無ければデフォルト値（`bigquery_yen_per_tb = 950.0`）で生成する。アプリ全体はこの 1 経路のみで設定へアクセスする運用とする。
- **DB で 1 行を強制しない理由**: SQLite で「最大 1 行」を制約として表現するのは煩雑（固定キー列＋一意制約等のハック）で、Rails の規約から外れる。シングルトン担保はアプリ層（`instance` 経由）に集約する方が単純で、`users` / `bigquery_connections` でアプリ層に検証を寄せている本リポジトリの方針とも一貫する。

### あえて今回入れていないもの

- **`bigquery_yen_per_tb` への CHECK 制約（`>= 0` 等）**: 数値・0 以上のバリデーションはモデル層（タスク記載の `numericality`）で担保する方針（`bigquery_connections` / `users` と同様）。
- **シングルトン強制用のカラム・一意インデックス**: 上記のとおりアプリ層で担保するため不要。
- **他の設定カラム**: `ApplicationSetting` は将来汎用設定を保持し得るが、本トピックで必要なのは `bigquery_yen_per_tb` のみ。他カラムは必要になった時点で別マイグレーションで追加する（YAGNI）。

---

## 3. モデル構成（実装段階で作成、本ドキュメントは設計の明記）

マイグレーション承認・実行後の実装で、以下を用意する（本ステップでは未作成、参考情報）。

`app/models/application_setting.rb`（モデル本体。シングルトン `instance` ／ `bigquery_yen_per_tb` のバリデーションは後続タスクで TDD 実装）

```ruby
class ApplicationSetting < ApplicationRecord
  validates :bigquery_yen_per_tb,
            numericality: { greater_than_or_equal_to: 0 }

  def self.instance
    first_or_create!
  end
end
```

`ApplicationSetting.table_name # => "application_settings"`（Rails 規約どおり）となり、本マイグレーションで作る `application_settings` テーブルに正しくマップされる。

---

## 4. 実行するマイグレーションコマンド（承認後に実行）

```bash
bin/rails db:migrate
```

- 影響 DB: development（`storage/development.sqlite3`）、test（`storage/test.sqlite3`）
- 実行後、`db/schema.rb` が `version: 20260531110000` に更新され、`application_settings` テーブル定義が反映される。

テスト DB を schema から再構築する場合:

```bash
bin/rails db:test:prepare
```

---

## 5. ロールバック方法

直前のマイグレーション（この `create_application_settings`）を取り消す:

```bash
bin/rails db:rollback
```

- `change` メソッドで定義しているため、`create_table` は自動的に逆操作（`drop_table`）でロールバックされる。
- ロールバック後は `db/schema.rb` の version が直前（`20260531100000`、`queries` まで）に戻る。

特定バージョンまで戻す場合:

```bash
bin/rails db:migrate:down VERSION=20260531110000
```

---

## 6. 影響範囲

- **development / test**: 新規テーブル追加のみ。既存テーブル（`users` / `bigquery_connections` / `queries`）への変更・データ移行はなし（破壊的変更なし）。
- **production**: 本ステップでは production への適用は行わない。production（`storage/production.sqlite3`、`db/migrate` パス）への反映は別途デプロイ時に検討する（Kamal の運用フローに従う）。
- **既存テスト**: 既存テーブルを変更しないため、既存スペックへの影響はなし。
- **後続実装への接続**: 本テーブル作成後、グループ2 の `ApplicationSetting` モデル（`instance` ／ バリデーション）、グループ1 の `CostEstimate`（`yen_per_tb` をこの設定から取得）の TDD 実装に進む。

---

## 7. マイグレーションファイルの内容（転記）

`db/migrate/20260531110000_create_application_settings.rb`

```ruby
class CreateApplicationSettings < ActiveRecord::Migration[8.1]
  def change
    create_table :application_settings do |t|
      t.decimal :bigquery_yen_per_tb, precision: 10, scale: 2, null: false, default: 950.0

      t.timestamps
    end
  end
end
```

---

## 8. 承認をお願いしたい内容・論点

### 承認をお願いしたい内容

- `application_settings` テーブルを新規作成する（破壊的変更なし）
- カラム: `bigquery_yen_per_tb`（decimal(10, 2), NOT NULL, default `950.0`）/ `created_at` / `updated_at`
- 追加インデックスなし
- シングルトン（1 行）担保はモデル層（`ApplicationSetting.instance`）で行い、DB では強制しない
- 適用先は development / test の 2 DB のみ（production は別途）

### 論点（要確認）

1. **precision/scale**: 金額単価として `precision: 10, scale: 2` を採用（最大 99,999,999.99）。この粒度・上限で問題ないか。
2. **デフォルト 950.0 の根拠**: $6.25/TB ≒ ¥950/TB を初期値とした。為替変動を踏まえつつもグローバル初期値として妥当との判断。この値で確定してよいか。
3. **シングルトンを DB で強制しない方針**: 1 行強制はアプリ層（`instance` 経由）に集約し、マイグレーションは通常の `create_table` のみとした。この方針で問題ないか。

**この内容で `bin/rails db:migrate` を実行してよいか、承認をお願いします。**
