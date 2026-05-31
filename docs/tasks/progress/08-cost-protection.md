# 作業進捗ログ — トピック08: コスト保護（dry-run・上限ガード）★

> タスク `docs/tasks/08-cost-protection.md` の作業ログ（時系列）。司令塔・Coder・Tester のアクションを記録。

- **ステータス**: ✅完了
- **担当**: Coder / Tester

## 司令塔メモ（着手時の判断・未決事項の決定）

- **新規マイグレーション必要**: `application_settings` テーブル（コスト単価のシングルトン設定）→ マイグレーション承認ゲート。
- **未決事項Dの決定**: 換算レートは **グローバル1設定**（`ApplicationSetting` シングルトン、`bigquery_yen_per_tb` decimal、デフォルト950.0）。Connection 単位ではない。タスク doc グループ2 も ApplicationSetting 前提で整合。
- **dry-run のSQL取得元**: ルートは `POST /queries/:query_id/dry_run`（接続コンテキスト取得用）。ただし **SQL本文はリクエストボディの現在のエディタ内容を使用**（ライブ編集中のコスト確認を成立させる。未保存の新規クエリは保存後に確認）。BigQuery 側 dry-run なので SQL を body で受けてもセキュリティ上問題なし。
- **命名**: `ApplicationSetting` はフラットなトップレベル（汎用シングルトン設定。将来他設定も保持し得る）。dry-run/コスト換算ロジックは PORO（`app/models/dry_run.rb` / `app/models/cost_estimate.rb`）と `Bigquery::Connection#over_limit?` に置く（`*Service` 禁止）。
- **命名読み替え**: タスク doc の `Connection#over_limit?` / `Connection#maximum_bytes_billed` は `Bigquery::Connection` に読み替え。`DryRun.new(connection, sql)` の connection は `Bigquery::Connection`。

## 時系列ログ

### 2026-05-31

- **司令塔**: トピック07完了を受け、依存（04・07）充足済みのトピック08（コスト保護★）に着手。新規 Coder をアサイン。`application_settings` テーブルのマイグレーションが必要 → 承認ゲート。確認用ドキュメント作成を指示。
- **Coder→司令塔**: `application_settings` マイグレーション＋確認ドキュメント作成。論点3点（precision(10,2) / デフォルト950.0 / シングルトンはアプリ層担保）を提起。司令塔: いずれも妥当と承認。
- **司令塔→人間**: `application_settings` マイグレーション承認を依頼。
- **人間→司令塔**: ✅承認。`db:migrate` 実行を許可。
- **司令塔→Coder**: マイグレーション実行＋トピック08 本実装（TDD）を指示。

### 2026-05-31（続き・Coder 本実装）

- **マイグレーション実行**: `bin/rails db:migrate`（承認済み）＋ `db:test:prepare`。`db/schema.rb` を `version: 20260531110000` に更新（`application_settings`: `bigquery_yen_per_tb` decimal(10,2) NOT NULL default 950.0 + timestamps）。commit「application_settings マイグレーション」。
- **PORO（`*Service` 禁止・TDD red→green）**:
  - `app/models/cost_estimate.rb`: `CostEstimate.new(bytes:, yen_per_tb:).estimate → { gb:, yen: }`。GB は GiB（1024³）、円は 1 TB = 1000 GB 単価（`yen = gb * yen_per_tb / 1000`）。5 GiB=5_368_709_120→`{gb:5.0, yen:4.75}`、0・1000GB(=1TB)→¥950 を検証。**byte↔GB 変換（`bytes_to_gb`/`gb_to_bytes`）を本 PORO に集約**（接続の GB 入力など他箇所からも参照）。
  - `app/models/dry_run.rb`: `DryRun.new(connection, sql).call → { bytes_processed: Integer }`。`connection.dry_run_job(sql)` 経由で課金ゼロ dry-run。**gem の dry-run は `QueryJob#bytes_processed` で返る**ため doc の `statistics.total_bytes_processed` から実 API に読み替え（specで instance_double スタブ）。
- **上限ガード（TDD）**:
  - `Bigquery::Connection#over_limit?(bytes_processed)`（nil は常に false、境界は超過扱いしない）。
  - `Bigquery::Connection#job_options`（`maximum_bytes_billed` があれば `{ maximum_bytes_billed: }`）＋ `#dry_run_job`（`query_job(sql, dryrun: true, **job_options)`）= **接続上限を BigQuery 側ジョブにも渡す共通組み立て**（実行ジョブはトピック10で接続）。
  - `app/models/limit_exceeded_error.rb`（`StandardError` 派生のドメイン例外）。
  - `ApplicationSetting`（`instance` シングルトン＝`first_or_create!`、`bigquery_yen_per_tb` の presence＋数値0以上）。
  - commit「DryRun/CostEstimate PORO と上限ガード」。
- **dry-run エンドポイント（TDD）**: `app/controllers/queries/dry_runs_controller.rb`、`POST /queries/:query_id/dry_run`（ルート `resources :queries do resource :dry_run, only: [:create], module: "queries" end`）。**所有者スコープ徹底**（`current_user.queries.find` で他人は 404）。SQL は**リクエストボディのライブ編集内容**を使用（未指定時のみ保存済みにフォールバック）。`DryRun`＋`CostEstimate`＋`over_limit?` で JSON `{ gb, yen, over_limit, limit_gb, error }`。上限超過は `over_limit:true` ＋「推定 X GB は接続の上限 Y GB を超えています」、BigQuery エラーは 422 ＋ `error`。request spec（正常/ライブSQL使用/超過/上限内/APIエラー/他人404）。commit「dry-runエンドポイント」。
- **コスト単価 admin 設定（TDD）**: `Admin::SettingsController`（singular `resource :settings`、`require_admin` で member 拒否→root）＋ `app/views/admin/settings/edit.html.erb`。request spec（admin 更新可・負値で 422・member 拒否）。commit「コスト単価 admin設定」。
- **ボス追加要望（接続のデータ上限を GB 入力・適用徹底）**:
  - `Bigquery::Connection#maximum_bytes_billed_gb`（GB↔bytes 仮想属性、換算は `CostEstimate` に集約）。接続フォームを **GB 入力 → bytes 保存**に変更（「現在の上限: ○ GB（= ○ bytes）」表示、空欄=上限なし維持）。コントローラの strong params を `maximum_bytes_billed_gb` に。既存 request/system spec を GB 入力に更新＋GB→bytes 保存の検証 spec を追加。commit「接続のコスト上限を GB 入力 → bytes 保存に変更」。
  - 上限のネイティブ適用は `#job_options`／`#dry_run_job` で実装済み（dry-run ジョブに `maximum_bytes_billed` を付与。実行ジョブはトピック10で同メソッドを使用）。dry-run の JSON/UI に接続上限（`limit_gb`）と `over_limit` を併記し、超過時に明示メッセージ。
- **フロント（Stimulus）**: `app/javascript/controllers/dry_run_controller.js`（SQL 変化を 500ms デバウンスで `POST /queries/:id/dry_run`、`data-dry-run-target="result"` に「推定 X.X GB / 約 ¥Y」、`over_limit` 時に警告バナー表示＋実行ボタン `disabled`）。保存済みクエリの編集フォーム（`queries/_form`）に dry-run コントローラ・結果/警告/submit ターゲットを配線（未保存の新規では無効）。rack_test system spec `spec/system/dry_run_spec.rb` で配線を検証。commit「dry-run Stimulus UI」。
- **品質ゲート（全て green/クリーン）**: `bundle exec rspec` = **208 examples / 0 failures**、SimpleCov **99.74%**（≥85%）。`bin/rubocop` 0 offense。`bin/brakeman --no-pager` **警告0**（dry-run の SQL injection 警告なし＝BigQuery 側 dry-run・パラメータ受け渡しで安全）。`bin/importmap audit` 脆弱性0。
- **マイグレーション追加**: なし（既存 `maximum_bytes_billed` カラムの活用のみ。新規テーブル/カラム不要）。
- **タスク doc / overview**: `08-cost-protection.md` の実装チェックボックス（グループ1〜6）を完了に・ステータス「完了」、`00-overview.md` 表の 08 を「完了」に更新。「動作確認」節は**実 BigQuery 接続が必要な手動確認のため未チェック**（Tester/手動で実施）。
- **Coder→司令塔**: 実装完了。Tester へ引き継ぎ。
- **司令塔→Tester**: トピック08 の QA（接続GB上限・dry-run弾き・ジョブ付与を含む）を依頼。
- **Tester→司令塔**: トピック08 QA **PASS**。全受け入れ条件＋ボス追加要望✅。CostEstimate換算（5GiB→{gb:5.0,yen:4.75}）・over_limit?・接続GB上限（10GB→10737418240 bytes・空欄nil維持・job_options/dry_run両系統反映）を rails runner で実機確認。rspec 208例0失敗・カバレッジ99.74%、rubocop no offenses、brakeman 0（SQLi警告なし）、importmap audit クリーン。差し戻し不要（軽微注記: member拒否はroot リダイレクト方式＝既存と一貫、実BigQuery目視項目は自動範囲外）。
- **司令塔**: トピック08 を **✅完了** と確定。
