# 作業進捗ログ — トピック05: 初回セットアップウィザード

> タスク `docs/tasks/05-setup-wizard.md` の作業ログ（時系列）。司令塔・Coder・Tester のアクションを記録。

- **ステータス**: 🔄進行中
- **担当**: Coder

## 司令塔メモ（着手時の判断）

- **新規マイグレーション不要**（既存 `User` / `Bigquery::Connection` を使用）→ マイグレーション承認ゲートなし。
- **命名読み替え**: タスク doc の `Connection` / `Connection#test_connection` は確定仕様の **`Bigquery::Connection` / `Bigquery::Connection#test_connection`** に読み替える。
- **未決事項の方針（実装者判断、司令塔承認）**:
  - step3: `datasets.list` 権限があれば、データセット0件でも「成功」扱い。
  - 不足権限の抽出: BigQuery の API エラー（`Google::Cloud::PermissionDeniedError` 等）の message/reason から抽出。実装時にエラー形を確認。
  - 進行状況インジケータ: 共通パーシャルに切り出してよい（過剰設計しない）。
  - step4 のコスト上限: バイト整数をそのまま保存する最小実装。
  - ウィザード完了後のリダイレクト先: クエリ一覧は未実装のため当面 `root_path`（dashboard）へ。

## 時系列ログ

### 2026-05-31

- **司令塔**: トピック04完了を受け、依存（03・04）充足済みのトピック05に着手。新規 Coder をアサイン。マイグレーション不要のため承認ゲートなし。

- **Coder**: 着手。既存実装（ApplicationController / Authentication / Bigquery::Connection / 各 spec パターン）を調査。新規マイグレーション不要を確認（既存 `User` / `bigquery_connections` のみ使用）。

- **Coder（commit: step3 接続テスト）**: TDD で `Bigquery::Connection#test_connection` を実装。
  - Red: `spec/models/bigquery/connection_spec.rb` に成功/権限不足（jobs.create・datasets.list）/複数不足/非権限エラーのケースを追加し失敗を確認。
  - 実装中に gem の実 API を確認。`Google::Cloud::Bigquery::Project#query` は `dry_run` 引数を持たないため、dry-run は **`query_job("SELECT 1", dryrun: true)`** を使用（`verify_partial_doubles` で発覚し修正）。`datasets.list` は `bigquery.datasets`。
  - Green: 不足権限は `Google::Cloud::Error`（PermissionDenied 等）の message から `bigquery.xxx.yyy` を正規表現で抽出。`datasets` が空配列でも成功扱い。`bundle exec rspec spec/models/bigquery/connection_spec.rb` → 24 examples, 0 failures。rubocop clean。

- **Coder（commit: 初回起動検知とウィザード骨格〜step1〜4）**: 
  - Red: `spec/requests/setup_wizard_spec.rb` を先に作成（初回誘導・完了済みリダイレクト・各ステップ GET/POST 正常/異常・進行制御）→ ルート未定義で失敗を確認。
  - Green: `config/routes.rb` に `/setup` 配下のステップルート追加、`ApplicationController#redirect_to_setup_if_needed`（`User.any?` 以外で `/setup/step1` へ）、`SetupWizardController`（step1 admin作成+セッション確立、step2 接続登録、step3 `test_connection` 診断、step4 コスト上限/スキップ→`root_path`）、各ビュー + 進行状況パーシャル `_progress.html.erb` を実装。
  - 設計判断: 完了済みリダイレクト（`User.any?`→root）は **入口（index/step1/create_step1）のみ**に限定。step2 以降は step1 完了済み（=User 存在）が前提のためループ回避。進行制御は `require_step1_completed`（User.none?→step1）/`require_step2_completed`（Connection.none?→step2）。
  - 既存リクエスト spec 3 件（sessions/authorization/bigquery connections の未ログイン系）が初回誘導で 302 化したため、各テスト先頭で `create(:user)` してユーザー存在状態に調整（新挙動と整合）。
  - `bundle exec rspec spec/requests/setup_wizard_spec.rb` → 23 examples, 0 failures。全体 → 0 failures、coverage 99.51%。rubocop clean。

- **Coder（commit: システムスペック）**: `spec/system/setup_wizard_spec.rb`（rack_test）を追加。0 件 → step1 → step2 → step3（`test_connection` スタブで成功）→ step4 スキップ → root の通しフロー、完了後 step1 アクセスで root へ戻る、接続テスト失敗時の不足権限表示を検証。2 examples, 0 failures。

- **Coder（完了報告）**: 全 RSpec green（113 examples, 0 failures）、SimpleCov 99.51%（≥85%）、`bin/rubocop` 0 offenses、`bin/brakeman --no-pager` 警告 0。`docs/tasks/05-setup-wizard.md` の全チェックボックス・ステータスを完了に、`00-overview.md` の表も完了に更新。Tester へ引き継ぎ。
</content>
