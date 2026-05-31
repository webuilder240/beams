# ADR 0001: BigQuery スキーマメタデータを SolidCache に保存する

- **Status**: Accepted
- **Date**: 2026-05-31
- **Deciders**: ボス / 司令塔 / Coder
- **Related**: トピック `docs/tasks/06-schema-browser.md`、進捗ログ `docs/tasks/progress/06-schema-browser.md`、対象モデル `Bigquery::Connection`（`app/models/bigquery/connection.rb`）

---

## Context

スキーマブラウザ（トピック06）は、左ペインのツリー UI で **データセット → テーブル → カラム**を探索し、テーブル名・カラム名をクリックするとクエリエディタに挿入できることをゴールとする（`docs/tasks/06-schema-browser.md` ゴール参照）。オートコンプリートは非スコープ（計画書 §5）。

メタデータの取得元は BigQuery の以下 API/クエリである:

- `datasets.list`（データセット一覧）
- `tables.list`（データセット内テーブル一覧）
- `INFORMATION_SCHEMA.COLUMNS`（テーブルのカラム定義。**データセット単位のクエリ**で、BigQuery のクエリ課金が発生し得る）

これらを **画面描画のたびに毎回叩くと問題がある**:

1. **レイテンシ**: 3 段の API/クエリを同期で叩くとツリー初期表示が遅い。ツリーは折りたたみ展開のたびに参照される。
2. **課金**: `INFORMATION_SCHEMA.COLUMNS` はクエリ課金対象。画面表示ごとに走らせるとコストが嵩む。
3. **要件**: トピック06はキャッシュ戦略として **TTL 24時間 + 手動更新ボタン + 初回アクセス時取得** を明示している。

ここで本質的な観察として、**スキーマメタデータは BigQuery を正本（source of truth）とする再生成可能なデータ**であり、アプリの永続的なドメインデータではない。失われても再取得すればよい。またツリー閲覧と名前挿入という現スコープでは、SQL での関係クエリ（JOIN・集計・部分検索）を必要としない（オートコンプリートが非スコープのため）。

本プロジェクトは Solid Stack（SQLite 完結）構成で、`solid_cache` を備える。

---

## Decision

BigQuery スキーマメタデータを **SolidCache（`Rails.cache`）に保存する**。専用テーブルへの正規化は行わない。

- **保存キー**: `"bigquery:schema:#{connection.id}"`（接続単位）。
- **値**: データセット → テーブル → カラムをネストした 1 個のハッシュ構造。

  ```ruby
  {
    fetched_at: Time,
    datasets: [
      {
        dataset_id: "analytics",
        name: "Analytics",
        tables: [
          {
            table_id: "events",
            table_type: "TABLE",
            columns: [
              { column_name: "user_id", data_type: "STRING", is_nullable: true, ordinal_position: 1 }
            ]
          }
        ]
      }
    ]
  }
  ```

- **TTL**: `Rails.cache.write(key, structure, expires_in: 24.hours)`。SolidCache のネイティブ失効に任せる。
- **同期ロジックの置き場所**: コーディング規約により `*Service` / `app/services` は禁止。**Active Record モデルメソッド**に置く。
  - `Bigquery::Connection#sync_schema!(force: false)`: BigQuery からネスト構造を組み立て `Rails.cache.write` で保存。`force: true` は無条件で再取得・上書き。
  - `Bigquery::Connection#cached_schema`: `Rails.cache.fetch(key, expires_in: 24.hours) { build_schema_structure }` 相当で、初回アクセス時取得と TTL を両立。
- **ネームスペース**: 既存 `Bigquery::Connection` 上のメソッドとして実装し、命名規約を統一する。表示用 PORO ラッパーは過剰設計を避け、原則ハッシュを直接扱う（必要時のみ薄い PORO を `app/models/bigquery/` 配下に追加）。
- **再同期**: `sync_schema!` は常にキー単位で **丸ごと上書き**する。差分 upsert は不要。

この決定により、新規テーブル・マイグレーションは不要になる（`db/schema.rb` は変更しない）。

---

## Alternatives Considered（代替案と却下理由）

### 1. 3 テーブル正規化（`bigquery_schema_datasets` / `bigquery_schema_tables` / `bigquery_schema_columns`）

当初案。データセット → テーブル → カラムの 1 対多階層を 3 テーブルに正規化し、複合 unique による upsert で永続化する案。

**却下理由**:

- **現スコープで関係クエリが不要**: ツリー閲覧と名前挿入だけが要件で、JOIN・部分検索・集計は使わない。**オートコンプリートは計画書 §5 でスコープ外**。正規化の主目的（関係クエリ・整合性）が現状活きない。
- **再生成可能データはキャッシュ層が適所**: スキーマは BigQuery を正本とする再生成可能データ。永続 DB に置くとメインの `storage/production.sqlite3` をスキーマメタデータで太らせ、**バックアップ対象を不必要に肥大化**させる。キャッシュ層（`production_cache.sqlite3`）なら失っても再取得でよく、バックアップ方針上も適切。
- **TTL がネイティブで扱える**: SolidCache は `expires_in` で失効を標準サポート。正規化テーブルだと `fetched_at` 比較ロジックを自前実装する必要があり、失効レコードの掃除も別途必要。
- **stale 問題が起きない**: キー単位の丸ごと上書きで再同期するため、BigQuery 側で削除されたデータセット/テーブル/カラムが残らない。正規化案では「今回取得しなかった行の削除（stale クリーンアップ）」を別途実装する負債が出る（当初 ADR でも Consequences として未解決だった）。
- **マイグレーション不要**: 3 つのマイグレーション・承認ゲート・スキーマ変更が一切不要になり、リードタイムと運用リスクが下がる。

必要になった場合（例: 将来オートコンプリートやスキーマ横断検索を実装する場合）は、改めて正規化テーブルを別 ADR で導入する余地を残す。

### 2. BigQuery を都度叩く（キャッシュなし）

却下。`INFORMATION_SCHEMA.COLUMNS` のクエリ課金と 3 段 API のレイテンシが画面表示ごとに発生し、TTL/手動更新要件・高速ツリー描画を満たせない。

### 3. メイン DB に 1 テーブル + JSON カラムで格納

却下。永続 DB を再生成可能データで太らせる点は正規化案 (1) と同様の難点があり、かつ JSON カラムでは TTL・失効をやはり自前実装する必要がある。SolidCache の `expires_in` を使う方が単純。

---

## Consequences

### Positive

- **マイグレーション不要**・スキーマ変更ゼロ。承認ゲートが不要になりリードタイム短縮。
- TTL（24時間）が `expires_in` で宣言的に書ける。
- キー単位の丸ごと上書きで **stale 行問題が原理的に発生しない**。
- 再生成可能データをキャッシュ層に置くことでメイン DB・バックアップを太らせない。
- ロジックは `Bigquery::Connection#sync_schema!` / `#cached_schema` のモデルメソッドに集約（`*Service` 禁止規約に適合）。

### Negative / 留意点

- **関係クエリができない**: スキーマに対する SQL 検索・JOIN・集計はできない。現スコープでは不要だが、将来オートコンプリートやスキーマ横断検索が必要になれば設計を見直す（その時点で別 ADR）。
- **blob サイズ**: 巨大スキーマ（多数データセット × 多数テーブル × 多数カラム）では 1 接続あたりのキャッシュ値が大きな blob になる。SolidCache のエントリサイズ・eviction の影響を受け得る。**eviction されても次アクセス時に再取得すればよい**ため許容する。著しく大きい場合は将来「データセット単位でキーを分割する」等の最適化余地がある。
- **同期実行方式**: 初回アクセス時取得は同期（before_action）で行う。データセット数が多い場合のレイテンシに注意（バックグラウンドジョブ化はトピック10で検討）。
- **テスト環境のキャッシュ**: test 環境のデフォルト `cache_store` は `:null_store`（書き込みが no-op）。本決定の検証のため、test では `:memory_store` に変更する（設定変更であり、マイグレーションではない）。
- **`INFORMATION_SCHEMA.COLUMNS` の取得粒度**（全データセット一括 vs オンデマンド）は課金観点で別途調整余地がある（トピック06 未決事項）。
