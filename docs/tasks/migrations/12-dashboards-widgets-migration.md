# マイグレーション確認用ドキュメント: `dashboards` / `widgets` テーブル作成

> トピック **12-dashboard**（ダッシュボード）の最初の作業。`Dashboard` と `Widget` の 2 テーブルを新規作成する。本ステップは**マイグレーション準備のみ**で、`db:migrate` / `db:test:prepare` は実行しない。
> **このドキュメントの承認後に `bin/rails db:migrate` を実行する。承認前は実行しない。**

- **対象マイグレーション**:
  - `db/migrate/20260531150000_create_dashboards.rb`（クラス名 `CreateDashboards`）
  - `db/migrate/20260531150001_create_widgets.rb`（クラス名 `CreateWidgets`）
- **テーブル名 / モデル名**: `dashboards` / `Dashboard`、`widgets` / `Widget`（いずれもフラットなトップレベル）
- **作成日**: 2026-05-31
- **担当**: Coder
- **ステータス**: 承認待ち（未実行）

> **作成順序の理由**: `widgets` は `dashboards` と `queries` を FK 参照するため、参照先の `dashboards` を先（`...150000`）に、`widgets` を後（`...150001`）に作成する。`queries` は既存（`20260531100000`）。

> **司令塔の確定方針（2026-05-31）**:
> - `Dashboard belongs_to :user`（所有者記録のみ。**閲覧/編集制限には使わない** ← 計画書 §4.9: ログインユーザーは全ダッシュボードを閲覧・編集可）、`Dashboard has_many :widgets, dependent: :destroy`。
> - `Widget belongs_to :dashboard` / `Widget belongs_to :query`。1 ダッシュボードに複数ウィジェット、同一クエリを複数ウィジェットに持てる（unique は張らない）。
> - ウィジェットが表示する内容は `Query#latest_succeeded_execution`（topic-10）の `#result`（`{schema:, rows:}`）。成功実行が無ければ「未実行」プレースホルダー（本体実装で対応）。チャート描画は `query.visualization`（topic-11、`has_one`）の `display_mode` に従う。
> - ウィジェットの設定値（位置・列幅・タイトル上書き）のみを保持し、結果データ本体は `query_executions` 側が保持するため二重持ちしない。

---

## 1. 追加するテーブル・カラム・制約・インデックス

### テーブル: `dashboards`（新規作成）

| カラム名 | 型 | NULL | デフォルト | 制約・備考 |
|----------|------|:----:|------------|-----------|
| `id` | integer (PK) | NOT NULL | 自動採番 | Rails 標準の主キー（自動付与） |
| `title` | string | NOT NULL | なし | ダッシュボード名。アプリ層で presence + 255 文字以内 validation |
| `description` | text | NULL 可 | なし | 説明文（任意）。未入力時は NULL |
| `user_id` | integer (references) | **NOT NULL** | なし | `users` への FK。所有者の記録のみ（閲覧/編集制限には使わない）。論点①で NOT NULL を推奨 |
| `created_at` | datetime | NOT NULL | なし | `t.timestamps` により自動付与 |
| `updated_at` | datetime | NOT NULL | なし | `t.timestamps` により自動付与。一覧の `updated_at DESC` 並びに使用 |

### テーブル: `widgets`（新規作成）

| カラム名 | 型 | NULL | デフォルト | 制約・備考 |
|----------|------|:----:|------------|-----------|
| `id` | integer (PK) | NOT NULL | 自動採番 | Rails 標準の主キー（自動付与） |
| `dashboard_id` | integer (references) | NOT NULL | なし | `dashboards` への FK。`belongs_to :dashboard`。**単独 index は張らず**、複合 index `[dashboard_id, position]` でカバー（論点②） |
| `query_id` | integer (references) | NOT NULL | なし | `queries` への FK。`belongs_to :query`。`t.references` で単独 index 付与 |
| `position` | integer | NOT NULL | `0` | ダッシュボード内の並び順。「上へ/下へ」で隣接ウィジェットと入れ替える。アプリ層で 0 以上の整数 validation |
| `column_span` | integer | NOT NULL | `1` | グリッド列幅。**1 or 2**（1=1カラム、2=2カラム幅）。許可値はアプリ層 validation で担保（論点④） |
| `title_override` | string | NULL 可 | なし | ウィジェットの表示タイトル上書き。**空（nil/blank）なら `Query#title` を使う**（`Widget#display_title`） |
| `created_at` | datetime | NOT NULL | なし | `t.timestamps` により自動付与 |
| `updated_at` | datetime | NOT NULL | なし | `t.timestamps` により自動付与 |

### インデックス

| テーブル | インデックス名 | 対象カラム | 種別 | 目的 |
|----------|----------------|-----------|------|------|
| `dashboards` | `index_dashboards_on_user_id` | `user_id` | 通常 | FK 結合・所有者参照。`t.references` で自動付与 |
| `widgets` | `index_widgets_on_query_id` | `query_id` | 通常 | FK 結合。`t.references` で自動付与 |
| `widgets` | `index_widgets_on_dashboard_id_and_position` | `[dashboard_id, position]` | 通常 | `ordered_widgets`（`widgets.order(:position)`）の絞り込み + 並べ替えに効く。`dashboard_id` 単独 index はこの複合 index の先頭で代替できるため**別途張らない**（`t.references :dashboard, index: false`） |

---

## 2. 各カラム・インデックスの目的・設計判断

### `dashboards`

- **`title`（string / NOT NULL）**
  ダッシュボード名。doc §Dashboard モデルの指定どおり NOT NULL。アプリ層で `presence: true` と `length: { maximum: 255 }` を担保する。string（SQLite では実質可変長）だが、UI・一覧表示で短い名称を想定するため string が適切。

- **`description`（text / NULL 可）**
  説明文。任意入力のため NULL を許容する。長文になり得るため text。

- **`user_id`（references / FK / NOT NULL）**
  ダッシュボードの所有者を記録する。**閲覧・編集制限には使わない**（計画書 §4.9: ログインユーザーは全ダッシュボードを閲覧・編集可。所有者は「誰が作ったか」の記録のみ）。`belongs_to :user`（`optional: false` デフォルト）に対応。`DashboardsController#create` で必ず `current_user` を `user_id` に設定する設計のため、**NOT NULL を推奨**（論点①）。doc のカラム表は `user_id:references`（NOT NULL 明記なし）だが、所有者なしのダッシュボードは想定されないため NOT NULL で安全網を張る。

- **`created_at` / `updated_at`**
  `t.timestamps` による標準のタイムスタンプ。一覧（`index`）は `updated_at DESC` で並べる（doc 受け入れ条件）。

### `widgets`

- **`dashboard_id`（references / FK / NOT NULL / 単独 index なし）**
  ウィジェットが属するダッシュボード。`belongs_to :dashboard` に対応。`Dashboard has_many :widgets, dependent: :destroy` でダッシュボード削除時にウィジェットも削除される（論点③）。
  **単独 index は `index: false` で抑止**し、代わりに複合 index `[dashboard_id, position]` を張る。複合 index の先頭カラムが `dashboard_id` のため、`dashboard_id` 単独での検索（`dashboard.widgets`）もこの複合 index で効く。単独 index を別途張ると冗長になるため省く（論点②）。

- **`query_id`（references / FK / NOT NULL）**
  ウィジェットが表示するクエリ。`belongs_to :query` に対応。`t.references` で単独 index を付与する。**unique は張らない**（同一クエリを複数のウィジェットで使える設計。例: 別ダッシュボードや同一ダッシュボード内で同じクエリを別の列幅で並べる）。

- **`position`（integer / NOT NULL / default `0`）**
  ダッシュボード内の表示順。`ordered_widgets`（`widgets.order(:position)`）で昇順に並べ、「上へ/下へ」ボタンで隣接ウィジェットと `position` を入れ替える（ドラッグ&ドロップなし、計画書 §4.8）。
  - **default を `0` にした理由**: doc の指定どおり。`create` 時は「末尾（現在の最大 position + 1）」に追加する設計（doc §WidgetsController）だが、DB default は安全側の `0` とする。
  - **NOT NULL の理由**: 順序のないウィジェットは並べ替え対象にできない。アプリ層で「0 以上の整数」を validation。
  - **一意制約は張らない（重要）**: 「上へ/下へ」の入れ替え途中で 2 件が一時的に同じ `position` を持ち得るため（A↔B のスワップを 2 回の UPDATE で行う等）。unique を張ると入れ替えの中間状態で制約違反になる。一意性はアプリ層のスワップロジックで担保する（論点②）。

- **`column_span`（integer / NOT NULL / default `1`）**
  グリッドの列幅。**1（1カラム幅）または 2（2カラム幅）**。CSS Grid で `column_span: 1` → `grid-column: span 1`、`column_span: 2` → `grid-column: span 2`（doc §ダッシュボード表示）。
  - **default を `1` にした理由**: doc の指定どおり。最も標準的な 1 カラム幅をフォールバックにする。
  - **NOT NULL の理由**: 列幅のないウィジェットはレイアウトできない。
  - **許可値 1/2 は DB CHECK を設けずアプリ層 validation（`inclusion: { in: [1, 2] }`）で担保**（既存テーブルと同方針。論点④）。

- **`title_override`（string / NULL 可）**
  ウィジェットの表示タイトルの上書き。**空（nil/blank）なら `Query#title` を表示する**（`Widget#display_title` メソッドで分岐。doc §Widget モデル）。多くのウィジェットはクエリ名をそのまま使うため、上書きは任意 → NULL 可。

- **`created_at` / `updated_at`**
  `t.timestamps` による標準のタイムスタンプ。

### あえて今回入れていないもの

- **`widgets` の結果データカラム**: ウィジェットが表示する結果（`{schema:, rows:}`）は `query_executions.result_blob` が保持する。ウィジェットは設定値（位置・列幅・タイトル上書き）のみで、結果を二重持ちしない。チャート種別・軸は `query.visualization`（topic-11）が保持する。
- **`widgets.position` の unique 制約**: 上記のとおり入れ替え中間状態を許容するため張らない。
- **`widgets.column_span` の DB CHECK 制約（1/2 の許可値）**: アプリ層 validation で担保（既存テーブルと同様、SQLite + アプリ層担保）。
- **`widgets.dashboard_id` の `on_delete: :cascade`（DB レベル FK カスケード）**: アプリ層の `has_many :widgets, dependent: :destroy` で担保するため DB FK にはカスケードを付けない（論点③）。

---

## 3. モデル構成（実装段階で作成、本ドキュメントは設計の明記）

マイグレーション承認・実行後の後続実装で、以下を用意する（本ステップでは未作成、参考情報）。

`app/models/dashboard.rb`

```ruby
class Dashboard < ApplicationRecord
  belongs_to :user
  has_many :widgets, dependent: :destroy

  validates :title, presence: true, length: { maximum: 255 }

  # position 昇順のウィジェット。show 画面の表示・並べ替えに使う。
  def ordered_widgets
    widgets.order(:position)
  end
end
```

`app/models/widget.rb`

```ruby
class Widget < ApplicationRecord
  COLUMN_SPANS = [ 1, 2 ].freeze

  belongs_to :dashboard
  belongs_to :query

  validates :position, numericality: { only_integer: true, greater_than_or_equal_to: 0 }
  validates :column_span, inclusion: { in: COLUMN_SPANS }

  # title_override が空なら query.title を返す。
  def display_title
    title_override.presence || query.title
  end
  # move_up/move_down（隣接ウィジェットとの position 入れ替え）等は後続タスクで TDD 実装。
end
```

> 補足（名称読み替え・実装確認結果）:
> - ウィジェットが表示する結果は `Query#latest_succeeded_execution`（`app/models/query.rb` L20-22。`query_executions.where(status: :succeeded).order(created_at: :desc).first`）の `#result`。
> - `QueryExecution#result`（`app/models/query_execution.rb` L28-33）は `result_blob` を Inflate して `{ schema: Array, rows: Array }` を返し、blob 未保存/空は **nil**。doc の `QueryExecution#result_data` は本実装の `result` を指す。成功実行が無い・結果が nil の場合は「未実行」プレースホルダーを表示する（本体実装で対応）。
> - チャート描画は `query.visualization`（`app/models/query.rb` L11 の `has_one :visualization, dependent: :destroy`。`Visualization belongs_to :query`）の `display_mode`（`table`/`chart`）に従い、topic-11 の描画（helper・`visualizations#show` の Turbo Frame 埋め込み）を再利用する。

---

## 4. 実行するマイグレーションコマンド（承認後に実行）

```bash
bin/rails db:migrate
```

- 2 件のマイグレーションが順に適用される（`...150000` dashboards → `...150001` widgets）。
- 影響 DB: development（`storage/development.sqlite3`）、test（`storage/test.sqlite3`）
- 実行後、`db/schema.rb` が `version: 20260531150001` に更新され、`dashboards` / `widgets` テーブル定義が反映される。

テスト DB を schema から再構築する場合:

```bash
bin/rails db:test:prepare
```

---

## 5. ロールバック方法

直前 2 件のマイグレーションを取り消す（widgets → dashboards の逆順で）:

```bash
bin/rails db:rollback STEP=2
```

- 両マイグレーションとも `change` メソッドで `create_table` を定義しているため、自動的に逆操作（`drop_table`）でロールバックされる（FK・index も併せて削除）。`widgets` は `dashboards` を FK 参照するため、`STEP=2` のロールバックは widgets を先に drop し、その後 dashboards を drop する正しい順序になる。
- ロールバック後は `db/schema.rb` の version が直前（`20260531140000`、`visualizations` まで）に戻る。

特定バージョンまで戻す場合:

```bash
bin/rails db:migrate:down VERSION=20260531150001  # widgets を先に
bin/rails db:migrate:down VERSION=20260531150000  # 次に dashboards
```

---

## 6. 影響範囲

- **development / test**: 新規テーブル 2 件の追加のみ。既存テーブル（`users` / `queries` 等）への変更・データ移行はなし（破壊的変更なし）。`users` への FK（dashboards）・`queries` への FK（widgets）を張るが、参照先テーブルの定義は変更しない（`has_many`/`has_one` 関連はモデル側のみで、既存テーブルへのカラム追加は不要）。
- **production**: 本ステップでは production への適用は行わない。production（`storage/production.sqlite3`、`db/migrate` パス）への反映は別途デプロイ時に検討する（Kamal の運用フローに従う）。
- **既存テスト**: 既存テーブルを変更しないため、既存スペックへの影響はなし。
- **後続実装への依存**: 本マイグレーションは純粋なスキーマ追加で、暗号化キーや外部 API に依存しない。

---

## 7. マイグレーションファイルの内容（転記）

`db/migrate/20260531150000_create_dashboards.rb`

```ruby
class CreateDashboards < ActiveRecord::Migration[8.1]
  def change
    create_table :dashboards do |t|
      t.string :title, null: false
      t.text :description
      t.references :user, null: false, foreign_key: true

      t.timestamps
    end
  end
end
```

`db/migrate/20260531150001_create_widgets.rb`

```ruby
class CreateWidgets < ActiveRecord::Migration[8.1]
  def change
    create_table :widgets do |t|
      t.references :dashboard, null: false, foreign_key: true, index: false
      t.references :query, null: false, foreign_key: true
      t.integer :position, null: false, default: 0
      t.integer :column_span, null: false, default: 1
      t.string :title_override

      t.timestamps
    end

    add_index :widgets, [ :dashboard_id, :position ]
  end
end
```

---

## 8. 承認をお願いしたい内容・論点

### 承認をお願いしたい内容

- `dashboards` テーブルを新規作成する（破壊的変更なし）
  - カラム: `title`(string, NOT NULL) / `description`(text, NULL) / `user_id`(references, FK, **NOT NULL**) / `created_at` / `updated_at`
  - インデックス: `user_id`（`t.references` で自動付与）
- `widgets` テーブルを新規作成する（破壊的変更なし）
  - カラム: `dashboard_id`(references, FK, NOT NULL, 単独 index なし) / `query_id`(references, FK, NOT NULL) / `position`(integer, NOT NULL, default `0`) / `column_span`(integer, NOT NULL, default `1`、許可値 1/2) / `title_override`(string, NULL) / `created_at` / `updated_at`
  - インデックス: `query_id`（自動）/ `[dashboard_id, position]`（複合・並べ替え用）
- 作成順序: `dashboards`（`...150000`）→ `widgets`（`...150001`）
- 適用先は development / test の 2 DB のみ（production は別途）

### 論点（司令塔に確認したい点 + Coder の推奨）

1. **`dashboards.user_id` を NOT NULL にする是非（推奨: NOT NULL）**
   doc のカラム表は `user_id:references`（NOT NULL 明記なし）だが、`DashboardsController#create` は必ず `current_user` を `user_id` に設定する設計のため、所有者なしのダッシュボードは想定されない。**Coder 推奨: NOT NULL**（`belongs_to :user` の `optional: false` デフォルトとも整合し、DB でも安全網を張る）。なお `user_id` は所有者の記録のみで、閲覧/編集制限には使わない（計画書 §4.9: ログインユーザーは全ダッシュボード閲覧・編集可）。

2. **`widgets` に `[dashboard_id, position]` 複合 index を張る是非・`position` の unique（推奨: 複合 index を張る / `position` unique は張らない）**
   `ordered_widgets`（`widgets.order(:position)`）はダッシュボードごとに position 昇順で取得するため、`[dashboard_id, position]` の複合 index が効く。`dashboard_id` 単独 index はこの複合 index の先頭で代替できるため `index: false` で省く（冗長回避）。
   一方、**`position` の一意制約は張らない**。「上へ/下へ」の入れ替え途中で 2 件が一時的に同じ position を持ち得る（2 回の UPDATE でスワップする中間状態）ため、unique を張ると制約違反になる。一意性はアプリ層のスワップロジックで担保する。**Coder 推奨: 複合 index を張る・`position` unique は張らない**。

3. **`dashboard` 削除時の `widgets` カスケード削除（推奨: アプリ層 `dependent: :destroy` で担保、DB FK カスケードは付けない）**
   doc の動作確認に「ダッシュボードを削除するとウィジェットも CASCADE 削除される」とある。これは `Dashboard has_many :widgets, dependent: :destroy`（アプリ層）で担保する。DB の FK に `on_delete: :cascade` を付けるかは、アプリ層 `dependent` で足りるため**付けない**（既存テーブルと同方針）。**Coder 推奨: アプリ層 `dependent: :destroy` のみ**。

4. **`column_span` の許可値（1/2）の担保方法（推奨: アプリ層 validation、DB CHECK なし）**
   `column_span` は 1 または 2 のみ許可。DB CHECK 制約は設けず、アプリ層 `validates :column_span, inclusion: { in: [1, 2] }` で担保する（既存テーブルと同方針）。**Coder 推奨: アプリ層 validation で確定**（DB default は `1`、NOT NULL）。

**この内容で `bin/rails db:migrate` を実行してよいか、承認をお願いします（本ステップではマイグレーション準備のみ・未実行）。**
