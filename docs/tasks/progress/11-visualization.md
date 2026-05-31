# 作業進捗ログ — トピック11: 可視化（Chart.js）

> タスク `docs/tasks/11-visualization.md` の作業ログ（時系列）。司令塔・Coder・Tester のアクションを記録。

- **ステータス**: 🔄進行中
- **担当**: Coder

## 司令塔メモ（着手時の判断・名称読み替え）

- **新規マイグレーション必要**: `visualizations` テーブル → **マイグレーション承認ゲート**（確認ドキュメント→人間承認→migrate）。
- **名称読み替え（タスク doc の前提名が実装と異なる）**:
  - `QueryExecution#result_data` → 実装は **`QueryExecution#result`**（Inflate→`{schema:, rows:}` を返す。topic-10）。空/未保存は nil。
  - CSV は **topic-10 の `Queries::Executions::CsvExportsController`（latest csv 経路, X-Sendfile）にリンクするのみ**。可視化側で CSV 生成しない（doc §CSVエクスポート・未決事項で確定済み）。
  - `Query has_one :visualization, dependent: :destroy`。
- **司令塔の決定**:
  - `y_columns` は **`text` に JSON 配列保存**（doc の `string` 表記は「JSON配列をtext保存」の意。`serialize`/`store_accessor` で `Array` 透過）。
  - 複数Y軸UIは **`<select multiple>`**（doc 未決事項の想定どおり、軽微につき司令塔判断）。
  - Chart.js は **CDN pin**（`bin/importmap pin chart.js`、doc で確定済み）。
  - `chart_type` 許可リスト `line/bar/pie/area/scatter`、`display_mode` `table/chart`。area は Chart.js `type:"line"+fill:true`。

## 時系列ログ

### 2026-05-31

- **司令塔**: トピック10完了（Tester PASS）を受け、依存（10・03・07）充足済みのトピック11に着手。新規 Coder をアサイン。`visualizations` テーブルのマイグレーションが必要 → 承認ゲート。まず確認用ドキュメント作成を指示（承認まで `db:migrate` 禁止）。
- **Coder→司令塔**: 確認ドキュメント `migrations/11-visualizations-migration.md`＋マイグレーションファイル `20260531140000_create_visualizations.rb`（未実行）作成。論点4点（query_id unique index / y_columns text+JSON / 軸カラム nullable / default 値）を推奨付きで提起。`QueryExecution#result_data`→実装は `#result`、CSV は topic-10 `latest_csv_query_executions_path` へリンクのみ、を確認。
- **司令塔→人間**: マイグレーション承認を依頼（司令塔レビュー済み、論点4点とも Coder 推奨に同意）。
- **人間→司令塔**: 「修正してほしい」。確認したところ **`chart_type` に counter（単一集計値を大きく表示する Redash 風カウンター）が無い** ことを指摘。ボス決定で **集計値表示（SUM/AVG/COUNT/MIN/MAX）** 方式に確定。
- **司令塔→Coder**: counter 追加要件を反映するよう指示（再承認ゲート・db:migrate 引き続き禁止）。`chart_type` 許可値に counter 追加（計6種）、マイグレーションに `counter_column`(string,NULL)・`counter_aggregation`(string,NOT NULL,default "sum"／sum/avg/count/min/max) 追加、集計は BigQuery 再クエリせず取得済み結果 rows にアプリ層で計算、counter は x/y/series 軸とは別系統、を確認ドキュメントに明記。
- **Coder→司令塔**: counter 対応を反映完了（マイグレーション＋確認ドキュメント更新、db:migrate 未実行）。既存カラム不変、`counter_column`/`counter_aggregation` を `display_mode` 直後に追加。
- **司令塔→人間**: 修正版マイグレーションの再承認を依頼（司令塔レビュー OK）。
- **人間→司令塔**: ✅**承認・実行する**。`db:migrate` 実行を許可。
- **司令塔→Coder**: マイグレーション実行＋トピック11 本体（Chart.js importmap pin / Visualization モデル・counter 集計 / コントローラ / テーブル⇄チャート切替 / 軸設定UI / Stimulus chart_controller / counter表示 / CSVリンク）を TDD で実装するよう指示。
