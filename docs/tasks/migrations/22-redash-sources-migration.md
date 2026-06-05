# マイグレーション確認用ドキュメント: `redash_sources` テーブル新規作成

> トピック **22-redash-import**（Redash クエリ取り込み・API版）の DB 変更。
> Redash サーバの接続情報（URL + 暗号化APIキー）を保存するためのテーブルを新規追加する。
>
> **このドキュメントの承認後に `bin/rails db:migrate` を実行する。承認前は実行しない。**

- **対象マイグレーション**: `db/migrate/YYYYMMDDHHMMSS_create_redash_sources.rb`
- **作成日**: 2026-06-06（マネージャー起票・未承認）
- **担当**: Coder（着手前）
- **ステータス**: 承認待ち（未実行）

---

## 1. 追加するテーブル

### テーブル: `redash_sources`（新規）

| カラム名 | 型 | NULL | デフォルト | 制約・備考 |
|---|---|:---:|---|---|
| `id` | integer (PK) | NOT NULL | 自動採番 | Rails 標準主キー |
| `name` | string | NOT NULL | なし | 表示名（例: `"社内Redash"`）。**一意** |
| `url` | string | NOT NULL | なし | Redash サーバの URL（例: `"https://redash.example.com"`）。HTTPS のみ、SSRF ガード対象 |
| `api_key` | text | NOT NULL | なし | Redash の User API Key。**Active Record Encryption で暗号化保存**（`Bigquery::Connection.service_account_json` と同方式） |
| `created_at` | datetime | NOT NULL | なし | `t.timestamps` |
| `updated_at` | datetime | NOT NULL | なし | `t.timestamps` |

**インデックス**:
| 名前 | 対象 | 種別 | 目的 |
|---|---|---|---|
| `index_redash_sources_on_name` | `name` | UNIQUE | 表示名の重複防止 |

> `api_key` は AR Encryption で暗号化されるためカラム自体はそのまま `text`。中身が暗号文になる。`Bigquery::Connection.service_account_json` の前例と一致。

---

## 2. マイグレーション本文（予定）

```ruby
# db/migrate/YYYYMMDDHHMMSS_create_redash_sources.rb
class CreateRedashSources < ActiveRecord::Migration[8.1]
  def change
    create_table :redash_sources do |t|
      t.string :name, null: false
      t.string :url,  null: false
      t.text   :api_key, null: false
      t.timestamps
    end

    add_index :redash_sources, :name, unique: true
  end
end
```

> モデル側で `encrypts :api_key` を宣言することで、書き込み時に Active Record Encryption が自動的に暗号化する。マイグレーション本文には encryption 関連の宣言は不要（モデル側で完結）。

---

## 3. 既存データへの影響

- なし。完全新規のテーブル追加。

---

## 4. ロールバック計画

```ruby
# bin/rails db:rollback STEP=1
# → drop_table :redash_sources で自動的に逆実行される
```

- ロールバック時に Redash 接続情報が消える。既に作成済みの `redash_sources` 行があれば失われるため、必要なら事前に `RedashSource.all.to_json` 等で書き出しを推奨（運用ドキュメント化は不要、開発作業中の話）。

---

## 5. テスト計画

### 5.1 マイグレーション単体

- `bin/rails db:migrate` 成功（development・test）
- `bin/rails db:rollback STEP=1` 成功
- `db/schema.rb` 反映確認

### 5.2 モデル単体

- `RedashSource.create!(name: "test", url: "https://example.com", api_key: "secret")` 成功
- `RedashSource.create!(name: "test", url: "...", api_key: "...")` を2回 → 2回目は一意制約違反
- 作成後、SQLite を直接覗いて `api_key` 列が平文 `"secret"` でないことを確認（暗号化されている）
- `RedashSource.first.api_key == "secret"` でアプリ越しには平文取得できる（AR Encryption の透過動作）

---

## 6. 承認

- [ ] ボス承認（_YYYY-MM-DD_）
- [ ] `bin/rails db:migrate` 実行
- [ ] `db/schema.rb` 反映確認
- [ ] テストDB 再構築（`bin/rails db:test:prepare`）
- [ ] モデルスペックで暗号化動作確認

承認なしでは Coder/Agent はこのマイグレーションを実行しない。
