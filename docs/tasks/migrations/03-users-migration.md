# マイグレーション確認用ドキュメント: `users` テーブル作成

> トピック **03-auth-users**（認証・ユーザー）の最初の作業。`User` モデルのテーブルを新規作成する。
> **このドキュメントの承認後に `bin/rails db:migrate` を実行する。承認前は実行しない。**

- **対象マイグレーション**: `db/migrate/20260531000928_create_users.rb`
- **作成日**: 2026-05-31
- **担当**: Coder
- **ステータス**: 承認待ち（未実行）

---

## 1. 追加するテーブル・カラム・制約・インデックス

### テーブル: `users`（新規作成）

| カラム名 | 型 | NULL | デフォルト | 制約・備考 |
|----------|------|:----:|------------|-----------|
| `id` | integer (PK) | NOT NULL | 自動採番 | Rails 標準の主キー（自動付与） |
| `email` | string | NOT NULL | なし | ログイン ID。下記の一意インデックスを付与 |
| `password_digest` | string | NOT NULL | なし | `has_secure_password`（bcrypt）が使うハッシュ格納カラム |
| `role` | string | NOT NULL | `"member"` | ロール（`"admin"` / `"member"` の 2 値を想定） |
| `created_at` | datetime | NOT NULL | なし | `t.timestamps` により自動付与 |
| `updated_at` | datetime | NOT NULL | なし | `t.timestamps` により自動付与 |

### インデックス

| インデックス名（自動） | 対象カラム | 種別 | 目的 |
|------------------------|-----------|------|------|
| `index_users_on_email` | `email` | UNIQUE | メールの重複登録を DB レベルで防止。ログイン時の検索高速化 |

---

## 2. 各カラムの目的・設計判断

- **`email`（NOT NULL / 一意）**
  メール+パスワード認証のログイン ID。アプリ側のバリデーション（一意・フォーマット）に加え、DB の一意インデックスで競合時の二重登録を確実に防ぐ。

- **`password_digest`（NOT NULL）**
  Rails 8 標準の `has_secure_password` が前提とするカラム名。bcrypt によるハッシュを格納する。平文パスワードは保存しない。`has_secure_password` を使うため、このカラム名は固定（変更不可）。

- **`role`（NOT NULL / デフォルト `"member"`）**
  認可に使うロール。`"admin"` / `"member"` の 2 種類（計画書 §4.1）。
  **デフォルトを `"member"` にした理由**: 最小権限の原則。ロール未指定で作成された場合に、誤って管理者権限を付与しないよう、権限の弱い `member` を既定とする。admin は明示的に指定したときのみ付与する。
  値の制約（2 値のみ許可）は次タスクで `User` モデルの `inclusion`/`enum` バリデーションとして実装する（DB の CHECK 制約は付けず、アプリ層で担保）。

- **`created_at` / `updated_at`**
  `t.timestamps` による標準のタイムスタンプ。監査・並び替えに使用。

### あえて今回入れていないもの
- `name` / `display_name` 等の表示名カラム: 現タスクのスキーマ要件（email / password_digest / role / timestamps）に含まれないため追加しない。必要になった時点で別マイグレーションで追加する。
- `role` の DB CHECK 制約 / enum 型: SQLite かつアプリ層（モデルの inclusion 検証）で担保する方針のため、今回は付けない。

---

## 3. 実行するマイグレーションコマンド（承認後に実行）

```bash
bin/rails db:migrate
```

- 影響 DB: development（`storage/development.sqlite3`）、test（`storage/test.sqlite3`）
- 実行後、`db/schema.rb` が `version: 20260531000928` に更新され、`users` テーブル定義が反映される。

テスト DB を schema から再構築する場合:

```bash
bin/rails db:test:prepare
```

---

## 4. ロールバック方法

直前のマイグレーション（この `create_users`）を取り消す:

```bash
bin/rails db:rollback
```

- `change` メソッドで定義しているため、`create_table` / `add_index` は自動的に逆操作（`drop_table`）でロールバックされる。
- ロールバック後は `db/schema.rb` の version が `0`（`users` テーブルなし）に戻る。

特定バージョンまで戻す場合:

```bash
bin/rails db:migrate:down VERSION=20260531000928
```

---

## 5. 影響範囲

- **development / test**: 新規テーブル追加のみ。既存テーブルへの変更・データ移行はなし（破壊的変更なし）。
- **production**: 本ステップでは production への適用は行わない。production（`storage/production.sqlite3`、`db/migrate` パス）への反映は別途デプロイ時に検討する（ONCE / Kamal の運用フローに従う）。
- **既存テスト**: 既存テーブルを変更しないため、既存スペックへの影響はなし。

---

## 6. マイグレーションファイルの内容（転記）

`db/migrate/20260531000928_create_users.rb`

```ruby
class CreateUsers < ActiveRecord::Migration[8.1]
  def change
    create_table :users do |t|
      t.string :email, null: false
      t.string :password_digest, null: false
      t.string :role, null: false, default: "member"

      t.timestamps
    end

    add_index :users, :email, unique: true
  end
end
```

---

## 7. 承認をお願いしたい内容（要約）

- `users` テーブルを新規作成する（破壊的変更なし）
- カラム: `email`(string, NOT NULL, 一意インデックス) / `password_digest`(string, NOT NULL) / `role`(string, NOT NULL, default `"member"`) / `created_at` / `updated_at`
- `role` のデフォルトは最小権限のため `"member"`
- 適用先は development / test の 2 DB のみ（production は別途）

**この内容で `bin/rails db:migrate` を実行してよいか、承認をお願いします。**
