# トピック13: 共有・権限（組織フルオープン） 進捗（時系列）

## 2026-05-31 着手〜完了

- 事前調査: `queries`・`dashboards` に `created_by_id` カラムが既存、`belongs_to :created_by` / `User#admin?` も実装済みのため **マイグレーション不要**と判定（承認ゲート対象外）。
- Coder13 が TDD で実装:
  - `Query` / `Dashboard` に `created_by_name`（作成者名 or "不明"）と `deletable_by?(user)`（作成者本人 or admin のみ true、nil は false）を追加。
  - `QueriesController#destroy` / `DashboardsController#destroy` に `authorize_deletion!` ガードを追加し、権限なしは `head :forbidden`（403）かつ destroy 実行せず。
  - 一覧/詳細（queries・dashboards の index・show）に作成者表示。削除ボタンを `deletable_by?(current_user)` でガード。
  - 追加 spec: model spec / request spec（403検証 queries・dashboards 両方）/ system spec（作成者表示・"不明"・削除ボタン表示有無）。
- Tester13 が独立検証（コード確認・rspec再実行・runner検算・lint/security再実行）で **PASS**。

## 結果
- rspec: 451 examples / 0 failures、SimpleCov 98.79%（≥85%）
- rubocop: 0 offenses / brakeman: 0 warnings
- コミット: a1f4c0e（model + model spec）, 2b9d3f7（destroy 403 ガード・作成者表示・削除ボタン制御 + request/system spec）

## 要件チェック
- 13.1 作成者表示（nil→"不明"）✅
- 13.2 削除権限（作成者・admin のみ、403、ボタン制御）✅
- 13.3 作成者名表示＋System spec ✅
