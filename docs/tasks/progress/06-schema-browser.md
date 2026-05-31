# 作業進捗ログ — トピック06: スキーマブラウザ・スキーマキャッシュ

> タスク `docs/tasks/06-schema-browser.md` の作業ログ（時系列）。司令塔・Coder・Tester のアクションを記録。

- **ステータス**: ✅完了
- **担当**: Coder / Tester

## 司令塔メモ（着手時の判断）

- **新規マイグレーション必要**: `schema_datasets` / `schema_tables` / `schema_columns` の3テーブル → マイグレーション承認ゲートに入る。
- **命名読み替え**: タスク doc の `Connection` / `Connection#sync_schema!` は確定仕様の **`Bigquery::Connection` / `Bigquery::Connection#sync_schema!`** に読み替える。スキーマモデルも `Bigquery` ネームスペース配下（`Bigquery::SchemaDataset` 等、テーブル `bigquery_schema_datasets` 等）に統一するか、フラット（`SchemaDataset`）にするかは確認用ドキュメントで提案させ、承認時に確定する。
- **07（クエリエディタ）依存部分の扱い（司令塔決定）**:
  - クエリエディタはトピック07で未実装。スキーマブラウザの「名前をエディタに挿入」は、Stimulus コントローラが**カスタムDOMイベント（例 `schema-browser:insert`、`detail` に挿入名）を dispatch する**実装にする。実際のエディタ側リスナは07で配線。
  - そのため `js: true` の「エディタに名前が入る」テストは07に委ねる。本トピックでは「クリックでカスタムイベントが発火する／クリップボードにコピーされる」ことをブラウザ非依存または最小の js テストで担保し、ツリーHTML・折りたたみ等は rack_test で担保する。
  - `js: true`（Playwright/chromium）が環境で実行不可な場合は、当該 system spec を pending とし rack_test カバレッジを厚くする。Coder は実行可否を報告すること。
- **sync_schema! の実行方式**: 初期は**同期（before_action）**。バックグラウンドジョブ化はトピック10で検討。
- **INFORMATION_SCHEMA.COLUMNS の取得粒度**: sync 実行時に全データセットを一括取得（最小実装）。

## 時系列ログ

### 2026-05-31

- **司令塔**: トピック05完了を受け、依存（04）充足済みのトピック06に着手。新規 Coder をアサイン。3テーブルのマイグレーションが必要 → 承認ゲート。確認用ドキュメント作成を指示。
- **Coder→司令塔**: 3テーブルのマイグレーション＋確認ドキュメント作成。論点3点（column upsertキーをcolumn_nameベースに / SQLite FK制約付与 / stale行クリーンアップはモデル実装で対応）を提起。司令塔: いずれも妥当と承認。
- **司令塔→人間**: 3テーブルのマイグレーション承認を依頼。
- **人間→司令塔**: 承認保留。**(1) 1テーブルずつ確認すること。(2) 各テーブルが必要な理由・利用要件を ADR にまとめて再提示すること。**
- **司令塔→Coder**: スキーマキャッシュ設計の ADR 作成を指示（`docs/adr/`）。作成後、司令塔が1テーブルずつ承認を取る。
- **人間→司令塔（重要な設計変更）**: 「クエリ結果（スキーマメタデータ）を SolidCache に保存するのではダメな理由は？」と問題提起。
- **司令塔→人間**: 3テーブル正規化 vs SolidCache vs JSONカラムを比較提示。現スコープ（ツリー閲覧＋名前挿入、オートコンプリートは§5でスコープ外）では関係クエリ不要で、スキーマは再生成可能データ→キャッシュ層が適所。SolidCache は TTL ネイティブ・上書き再同期で stale 問題なし・マイグレーション不要、と回答。
- **人間→司令塔**: **SolidCache 方式を採用**（決定）。
- **司令塔（確定）**: スキーマキャッシュは **SolidCache（`Rails.cache`）に保存**する方式へ変更。3テーブルのマイグレーション（20260531093001〜093003）と確認ドキュメント `06-schema-cache-migration.md` は破棄。ADR 0001 を SolidCache 決定に書き換え（3テーブル案は却下代替案として残す）、タスク doc 06 を SolidCache 方式に改訂。**マイグレーション不要のため承認ゲートなし**。ロジックは `Bigquery::Connection#sync_schema!` / `#cached_schema` 等のモデルメソッドに（`*Service` 禁止）。

### 2026-05-31（続き・SolidCache 方式の実装）

- **Coder**: ボス決定（SolidCache 方式）を受け、不要成果物を整理。
  - 削除: `db/migrate/20260531093001〜093003`（3マイグレーション）、`docs/tasks/migrations/06-schema-cache-migration.md`。`db/schema.rb` は変更なし。
  - 改訂: ADR 0001 を SolidCache 採用（Status: Accepted）に書き換え。3テーブル正規化案は Alternatives Considered（却下）へ移動し却下理由を明記（現スコープで関係クエリ不要＝オートコンプリート§5外 / 再生成可能データはキャッシュ層が適所＝バックアップを太らせない / TTLネイティブ / 丸ごと上書きで stale 問題なし / マイグレーション不要）。Consequences に SolidCache の留意点（blobサイズ・evictは再取得で許容、関係クエリ不可、test は memory_store）を記載。
  - 改訂: タスク doc 06 を SolidCache 方式に全面書き換え（`SchemaDataset/Table/Column` 前提のタスクを削除し、`Bigquery::Connection#sync_schema!`/`#cached_schema` 前提に）。
- **Coder（TDD）**: `spec/models/bigquery/connection_spec.rb` にスキーマキャッシュ spec を追加 → red 確認 → 実装で green。
  - `Bigquery::Connection#sync_schema!(force:)`: datasets.list / tables.list / `INFORMATION_SCHEMA.COLUMNS` を取得しネスト構造を `Rails.cache.write("bigquery:schema:#{id}", ..., expires_in: 24.hours)`。`force: true` で無条件上書き。
  - `#cached_schema`: `Rails.cache.fetch` で初回取得とTTL両立。
  - 検証: sync 書き込み / キャッシュ再利用（datasets 1回）/ `travel 25.hours` 失効再取得 / `travel 1.hour` キャッシュ利用 / force 上書き。
  - test 環境の `cache_store` を `:null_store` → `:memory_store` に変更（キャッシュ検証のため。設定変更でありマイグレーションではない）。
- **Coder**: UI・コントローラ・ルート実装。
  - `SchemaBrowsersController#show`（before_action で先頭接続の `cached_schema`）、`SchemaCachesController#refresh`（`sync_schema!(force: true)` → リダイレクト）。
  - ルート: `get /schema_browser`、`resources :schema_caches do collection { post :refresh } end`。
  - ビュー `app/views/schema_browser/_schema_browser.html.erb`（datasets→tables→columns ネストリスト、`data-controller="schema-browser"`、手動更新ボタン）+ `schema_browsers/show.html.erb`。
  - Stimulus `schema_browser_controller.js`（折りたたみ展開トグル、名前クリックで `schema-browser:insert` dispatch + クリップボードコピー）。
  - spec: request（schema_caches / schema_browsers）、rack_test system spec（ツリーHTML確認）。`js: true` のエディタ挿入は **トピック07へ委譲し pending**（理由をテスト内に明記）。
- **結果**: `bundle exec rspec` 全体 126 examples / 0 failures / 1 pending、SimpleCov **99.6%**（≥85%）。`bin/rubocop` 0 offenses、`bin/brakeman --no-pager` 警告0。**マイグレーションは発生していない**。
- **ステータス更新**: 🔄進行中 → ✅完了（00-overview.md の表も完了に更新）。Tester へ引き継ぎ。
- **司令塔→Tester**: トピック06（SolidCache方式）の QA を依頼。
- **Tester→司令塔**: トピック06 QA **PASS**。改訂後の全受け入れ条件✅、設計変更の整合性も確認（schema系テーブル/マイグレーション無し・確認doc削除済み・ADR 0001 Accepted）。rspec 126例 0 failures 1 pending（js:trueエディタ挿入=07委譲）・カバレッジ99.6%、rubocop no offenses、brakeman 0。実機round-trip（sync_schema!→cached_schema）確認。軽微指摘1件（Stimulus未宣言target、実害なし）。差し戻し不要。
- **司令塔**: トピック06 を **✅完了** と確定。
