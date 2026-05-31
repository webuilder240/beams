# トピック05: 初回セットアップウィザード

> 初回起動（ユーザー 0 件）を検知し、admin アカウント作成・BigQuery 接続登録・接続テスト・コスト上限設定を段階的に誘導するウィザードを実装する。計画書 §4.10 に対応。

- **ステータス**: 完了
- **依存**: [[03-auth-users]]（`User` モデル・セッション管理・admin 認可が完了していること）、[[04-bigquery-connection]]（`Connection` モデル・`Connection#bigquery` が完了していること）
- **関連計画書**: §4.10

## ゴール（完了の定義）

- ユーザーが 0 件の状態でアプリにアクセスするとウィザードにリダイレクトされる
- ウィザードはステップ①〜④を順番に進める（前のステップ未完了なら先へ進めない）
- ①: admin アカウントを作成してセッションを確立できる
- ②: BigQuery 接続（SA JSON + プロジェクト ID）を登録できる
- ③: 実際に BigQuery API（dry-run + `datasets.list`）を叩いて接続テストを行い、成功/不足権限を具体的に診断・表示できる
- ④: コスト上限（`maximum_bytes_billed`）を任意で設定できる（スキップ可）
- ウィザード完了後は通常のアプリ（クエリ一覧等）にリダイレクトされる
- ウィザード完了済み（ユーザーが 1 件以上）の状態でウィザード URL にアクセスするとルートにリダイレクトされる
- RSpec で主要パスがカバーされ、SimpleCov 85% 以上を維持する

## 前提・参照

- [[03-auth-users]]: `User` モデル、`has_secure_password`、`current_user`, `logged_in?`, `require_login`
- [[04-bigquery-connection]]: `Connection` モデル（`service_account_json`、`project_id`、`maximum_bytes_billed`）、`Connection#bigquery`（BigQuery クライアントを返すモデルメソッド）
- BigQuery dry-run: `client.query("SELECT 1", dry_run: true)` でコスト見積もりのみ実行（課金ゼロ）
- BigQuery `datasets.list`: `client.datasets` でデータセット一覧を取得（権限確認に使用）
- 計画書の接続テスト診断例: `bigquery.jobs.create` 権限が無い場合などを具体的にメッセージ表示

## タスク

### 初回起動検知とリダイレクト

- [x] `ApplicationController` に初回起動検知ロジック追加（`app/controllers/application_controller.rb`）— `before_action :redirect_to_setup_if_needed`。`User.none?` の場合にウィザードトップにリダイレクト。ウィザードコントローラ自身のアクションでは skip する
  - 受け入れ条件: `User` テーブルが空の状態で任意の URL にアクセスすると `/setup` にリダイレクトされる。`User` が 1 件以上のときはリダイレクトしない
- [x] ウィザード完了済みチェック（`app/controllers/setup_wizard_controller.rb`）— `User.any?` のときウィザード URL にアクセスするとルートにリダイレクト
  - 受け入れ条件: ウィザード完了後にブラウザで `/setup` にアクセスするとルートに戻される

### SetupWizardController と Routing

- [x] `SetupWizardController` 作成（`app/controllers/setup_wizard_controller.rb`）— ステップ管理のベースコントローラ。`step1`〜`step4` のアクション（`show`/`create` に相当する `GET`/`POST`）を持つ
  - 受け入れ条件: `rails routes` でウィザードの各ステップパスが確認できる
- [x] ルーティング追加（`config/routes.rb`）— `/setup` 以下にウィザードのステップルーティング（例: `get "setup/step1"`, `post "setup/step1"` など。ステップ数に応じて定義）
  - 受け入れ条件: `rails routes` で step1〜step4 の GET/POST パスが存在する
- [x] ステップ間の進行制御（`app/controllers/setup_wizard_controller.rb`）— 各ステップ開始前に前のステップの完了を確認（例: step2 開始前に `User.any?`、step3 開始前に `Connection.any?`）。未完了なら前のステップにリダイレクト
  - 受け入れ条件: step3 に直接アクセスしても step2 を完了していなければ step2 にリダイレクトされる

### ステップ① admin アカウント作成

- [x] step1 アクション実装（`app/controllers/setup_wizard_controller.rb`）— `GET` でフォーム表示、`POST` で `User` を admin ロールで作成・セッション確立
  - 受け入れ条件: フォームに email + password + password_confirmation を入力して送信すると admin User が作成され、セッションが確立されて step2 にリダイレクトされる。バリデーションエラー時はフォームに戻る
- [x] step1 ビュー作成（`app/views/setup_wizard/step1.html.erb`）— email・password・password_confirmation フィールド、送信ボタン、ウィザードの進行状況インジケータ
  - 受け入れ条件: `/setup/step1` でフォームが表示される

### ステップ② BigQuery 接続登録

- [x] step2 アクション実装（`app/controllers/setup_wizard_controller.rb`）— `GET` でフォーム表示、`POST` で `Connection` を作成（`name`, `project_id`, `service_account_json`。`maximum_bytes_billed` は step4 で設定するため初期値 NULL）
  - 受け入れ条件: SA JSON テキスト + プロジェクト ID を入力して送信すると `Connection` が保存されて step3 にリダイレクトされる。バリデーションエラー時はフォームに戻る
- [x] step2 ビュー作成（`app/views/setup_wizard/step2.html.erb`）— `name`, `project_id`, `service_account_json`（`<textarea>`）フィールド、送信ボタン、進行状況インジケータ
  - 受け入れ条件: `/setup/step2` でフォームが表示される

### ステップ③ 接続テスト（具体診断）

- [x] `Connection#test_connection` モデルメソッド実装（`app/models/connection.rb`）— `Connection#bigquery` を利用して①dry-run（`SELECT 1`）と②`datasets.list` を実行し、`{ success: true }` または `{ success: false, missing_permissions: ["bigquery.jobs.create", ...], message: "..." }` を返す。**TDD**: 先に失敗する RSpec を `spec/models/connection_spec.rb` に書いてから実装する
  - 受け入れ条件: BigQuery クライアントをモックして、`Google::Apis::ClientError` の `status_code` や `message` から不足権限名を取り出して返せる。`bundle exec rspec spec/models/connection_spec.rb` がグリーンになるまでタスク完了にしない
- [x] `Connection#test_connection` の単体テスト（`spec/models/connection_spec.rb`）— **先に失敗するテストを書く（TDD）**。成功ケース・権限不足ケース（エラーメッセージから `bigquery.jobs.create` などを抽出できるか）・その他の失敗ケース
  - 受け入れ条件: `bundle exec rspec spec/models/connection_spec.rb` がグリーン（外部 API 呼び出しなし）。カバレッジ 85% 以上を維持
- [x] step3 アクション実装（`app/controllers/setup_wizard_controller.rb`）— `GET` で `Connection.first.test_connection` を呼び出して結果を表示。「成功」なら step4 へのリンク、「失敗」なら不足権限リストと再試行リンクを表示
  - 受け入れ条件: 接続テスト成功時に成功メッセージと「次へ」ボタンが表示される。失敗時に不足権限（例: `bigquery.jobs.create`）が具体的に表示される
- [x] step3 ビュー作成（`app/views/setup_wizard/step3.html.erb`）— テスト結果（成功/失敗）、不足権限リスト、再テストリンク、進行状況インジケータ
  - 受け入れ条件: `/setup/step3` でテスト結果が表示される

### ステップ④ コスト上限設定（任意・スキップ可）

- [x] step4 アクション実装（`app/controllers/setup_wizard_controller.rb`）— `GET` でフォーム表示、`POST` で `Connection` の `maximum_bytes_billed` を更新してウィザード完了、クエリ一覧へリダイレクト。スキップボタンも用意（`maximum_bytes_billed` を NULL のままで完了）
  - 受け入れ条件: 値を入力して送信すると `Connection.first.maximum_bytes_billed` に値が入り、クエリ一覧にリダイレクトされる。スキップしても同様にリダイレクトされ、`maximum_bytes_billed` は NULL のまま
- [x] step4 ビュー作成（`app/views/setup_wizard/step4.html.erb`）— `maximum_bytes_billed` 入力欄、単位の補足（例: バイト数入力、または TB 換算の説明）、送信ボタン、スキップリンク、進行状況インジケータ
  - 受け入れ条件: `/setup/step4` でフォームが表示され、スキップリンクが存在する

### RSpec テスト

- [x] `SetupWizardController` のリクエストスペック（`spec/requests/setup_wizard_spec.rb`）— 初回起動リダイレクト、各ステップの GET/POST 正常系・バリデーションエラー系、ステップ間の順序制御、ウィザード完了済みでのリダイレクト
  - 受け入れ条件: `bundle exec rspec spec/requests/setup_wizard_spec.rb` がグリーン
- [x] ウィザードのシステムスペック（`spec/system/setup_wizard_spec.rb`）— rack_test ドライバー。ユーザー 0 件でアクセス → step1 → step2 → step3（接続テストはスタブ） → step4（スキップ）→ クエリ一覧 という一連のフローを検証
  - 受け入れ条件: `bundle exec rspec spec/system/setup_wizard_spec.rb` がグリーン

## 動作確認

- [x] `rails db:migrate` → `User` / `Connection` テーブルが空の状態でサーバーを起動
- [x] ブラウザで `/` にアクセス → `/setup/step1` にリダイレクトされる
- [x] step1: admin メール + パスワードを入力して送信 → step2 に進む
- [x] step2: SA JSON テキストとプロジェクト ID を入力して送信 → step3 に進む
- [x] step3: 接続テスト結果が表示される（実際の BigQuery 接続がある場合は成功/失敗が確認できる）
- [x] step4: コスト上限を入力またはスキップ → クエリ一覧（またはルート）にリダイレクトされる
- [x] ウィザード完了後に `/setup/step1` にアクセス → ルートにリダイレクトされる
- [x] `bundle exec rspec spec/requests/setup_wizard_spec.rb spec/models/connection_spec.rb spec/system/setup_wizard_spec.rb` → 全グリーン
- [x] `bundle exec rspec` → SimpleCov 85% 以上

## 未決事項・質問

- step3 の接続テスト（`datasets.list`）でデータセットが 0 件のプロジェクトは「成功」扱いか「失敗」扱いか。`bigquery.datasets.list` 権限があれば空リストは正常と判断する方針でよいか確認が必要。
- `Connection#test_connection` でエラーメッセージから不足権限名を抽出するロジックは BigQuery の API エラー形式に依存するため、実装時にエラーレスポンスの実例を確認して抽出パターンを決める。
- ウィザードの進行状況インジケータ（step 1/2/3/4 の表示）を共通レイアウトとして切り出すか、各ビューに個別に書くか。計画書に指定なし。
- step4 のコスト上限入力 UI の単位（バイト直接入力か GB/TB 換算入力か）は [[04-bigquery-connection]] の未決事項と共通。本トピックでは入力値をバイト整数としてそのまま保存する最小実装を想定。
