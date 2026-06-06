# マネージャー管理ログ — トピック20: SSO（Google OAuth ログイン）

> Coder の実装ログ（`docs/tasks/progress/20-sso.md`）とは別の、マネージャーによる管理・実測検証ログ。偽の数値・ハッシュは書かない。

- **タスク定義**: [docs/tasks/20-sso.md](../20-sso.md)
- **マイグレーション資料**: [docs/tasks/migrations/20-users-oauth-migration.md](../migrations/20-users-oauth-migration.md)
- **ブランチ**: `feat/20-sso`（worktree `.claude/worktrees/feat-20-sso` で Coder 作業）
- **体制**: マネージャー1 / Coder 1 / Tester 1 / Reviewer 1

## ボス決定事項（2026-06-06 確定済み）

20-sso.md 内表参照。要約:

- B1: Google OAuth のみ（拡張余地は `oauth_identities` に残す）
- B2: gem は `omniauth` + `omniauth-google-oauth2` + `omniauth-rails_csrf_protection`
- B3: ENV 保管（`GOOGLE_OAUTH_CLIENT_ID` / `..._SECRET`）。`ApplicationSetting` には `allowed_email_domain` のみ
- B4: email 突合で1人1User（既存 email は identity 追加でリンク）
- B5: domain allowlist + 自動作成（`role: "member"`）
- B6: 初回 admin はパスワードのみ（OAuth は setup 後）
- B7: ENV 設定時のみ Google ボタン表示
- B8: `User#password=` / `#password_confirmation=` / `#authenticate` を `PasswordCredential` 委譲
- B9: PC 無し時 `authenticate` は `false`

## マイグレーション承認（2026-06-06、`/agent-team` 着手時に取得）

ボス承認: **`users.password_digest` を `password_credentials` 別テーブルに移行・カラム削除を含む破壊的マイグレーション 3本**（`create_password_credentials_and_migrate` / `create_oauth_identities` / `add_allowed_email_domain_to_application_settings`）。`docs/tasks/migrations/20-users-oauth-migration.md` の内容通り。

Coder 実行時の手当て:
- 事前に `storage/development.sqlite3.bak-20-sso` を作成
- `db:migrate` 後、`db:rollback STEP=3` 双方向確認
- 既存ユーザーのパスワードで bcrypt 一致確認（手動）

## 基線（着手前の実測、2026-06-06 マネージャー実測）

- `bin/rails db:test:prepare` 実行済み
- `bundle exec rspec` フルスイート: **513 examples / 0 failures**、Line Coverage **98.88% (973/984)**
- `bin/rubocop`: **147 files inspected, no offenses detected**

## 実行サイクル記録

| グループ | 内容 | 状態 | マネージャー実測 |
|---|---|:---:|---|
| 全体 | SSO実装（gem+initializer / migration / models / controller+routes / views / tests / docs+ADR） | ✅Coder完了・マネージャー検証済 | 下記参照 |
| リファクタ | Reviewer 指摘 must+should 全件対応 | ✅Coder完了・マネージャー検証済 | 下記参照 |

## マネージャー実測検証（Coder 一次完了後、2026-06-06）

Coder（worktree `feat-20-sso`、ブランチ `feat/20-sso`）の報告を実測で再現。

- **コミット実在**: 3件すべて `git cat-file -t` で commit 確認:
  - `284f079` omniauth gem 追加と initializer
  - `4c158de` identity テーブル分離（password_credentials / oauth_identities）
  - `614bab5` OmniAuth callback / ログインボタン / admin allowed_email_domain UI
- **`bundle exec rspec`** フルスイート: **549 examples / 0 failures**、Line Coverage **98.87% (1047/1059)**。基線 513 から +36（identity モデル+OAuth+ApplicationSetting+SSO system+admin settings 拡張）。
- **`bin/rubocop`**: **159 files inspected, no offenses detected**。
- **`bin/brakeman --no-pager`**: Errors 0 / Security Warnings 0。
- **`bin/bundler-audit`**: No vulnerabilities found。
- **要件外/逆実装チェック**:
  - `app/services/` 不在、`grep -rn "Service\b" app/ lib/ --include="*.rb"` → コメント中言及のみ（`*Service` 命名なし） ✓
  - `db/schema.rb`: `users.password_digest` 削除済（1件のみ＝`password_credentials` 側）、`password_credentials` / `oauth_identities` / `application_settings.allowed_email_domain` 追加反映 ✓
  - `storage/development.sqlite3.bak-20-sso` 存在（事前バックアップ） ✓
- **要件充足（実読確認）**:
  - `config/initializers/omniauth.rb`: ENV ガード + test 環境のダミー登録 ✓
  - `app/controllers/auth/omniauth_callbacks_controller.rb`: `google_oauth2` / `failure` / `passthru`、`reset_session` → `session[:user_id]` セット、nil 戻り時 alert ✓
  - `app/models/user.rb`: 仮想属性経由、`authenticate` 委譲（self 返却）、`find_or_create_for_oauth` 4 分岐 ✓
  - `app/views/sessions/new.html.erb`: ENV ガード付き Google ボタン ✓
  - routes: `GET /auth/google_oauth2/callback`、`GET /auth/failure`、`match POST/GET /auth/:provider`（GET 受けは Reviewer 指摘でリファクタ対象）

### マネージャー所見・要追跡

- routes が `match via: [:get, :post]` で GET も受けている（仕様は POST のみ）→ Reviewer 領域に申し送り
- test 環境では provider が無条件で登録される → Reviewer 領域に申し送り
- admin allowed_email_domain UI のテストが System ではなく request spec（System 層は sso_spec が間接的にカバー）→ Reviewer 領域に申し送り

## Tester QA 結果（2026-06-06、Tester 独立検証）

- Tester 自身の実測: フルスイート **549 examples / 0 failures**、Line Coverage **98.87%** を再現。
- 受け入れ条件: ゴール 9 項目・動作確認 11 項目すべて **PASS**。
- ボス決定事項 B1〜B9 反映確認: 全 **PASS**。
- 仕様逸脱: なし（マネージャーが申し送った 3 点は QA 観点でブロッカーではなく Reviewer 領域として再確認）。
- **総合判定: PASS**。Reviewer へ引き継ぎ。

## Reviewer レビュー結果（2026-06-06、Reviewer 独立レビュー）

`reviewer` 観点（コード品質・設計制約・重複/単純化/効率）で **must 2件・should 8件・nice-to-have 11件** の findings:

| ID | 重要度 | 概要 |
|---|---|---|
| A | must | `User#authenticate` まわりの after_save 設計を明示化（条件メソッド名で意図を示す） |
| B | must | `find_or_create_for_oauth` 既存 email リンクが `oauth_identities.create!` 直叩き → 冪等化が必要 |
| C | should | `find_or_create_for_oauth` 全体をトランザクション化（内側 transaction 重複を排除） |
| D | should | `Rails.configuration.x.sso_enabled` フラグで initializer/view の判定を一元化 |
| F | should | routes を `match GET+POST` → `post` のみに（CSRF 意図と整合） |
| I | should | `down` マイグレーションで OAuth 限定ユーザー検出時に `IrreversibleMigration` を raise |
| J | should | `password_confirmation` の空文字を `PasswordCredential` に伝える |
| M | should | `find_or_create_for_oauth` 先頭で email blank ガード |
| R | should | 仮想属性 `password` のリセット副作用を整理（dirty tracking への影響回避） |
| T | should | System Spec の ENV 直書きを `Rails.configuration` トグルに変更（D とセット） |
| E,G,H,K,L,N,O,P,Q,S,U | nice-to-have | （見送り） |

### ボス判断（2026-06-06）

- **must + should 全件適用**（A, B, C, D, F, I, J, M, R, T）
- **finding B の厳しさ**: 冪等化のみ（`find_or_create_by!(provider:, uid:)` 化、DB 制約追加せず、追加マイグレーション不要）
- nice-to-have は見送り（理由: 動作影響なし・Tester PASS・追加コストに見合わない）

## Coder リファクタ対応・マネージャー再検証（2026-06-06）

Coder のリファクタ報告を実測で再現。

### 追加コミット（実在確認済）

- `7305f66` refactor(20-sso): User の認証/同期 callback を明示化 (A,B,C,J,M,R)
- `894bfdb` refactor(20-sso): SSO 有効化フラグを `Rails.configuration` に集約 (D,T)
- `f2c7371` refactor(20-sso): routes と migration の安全性向上 (F,I)
- `6809709` docs(20-sso): Reviewer 指摘リファクタの対応記録を追加

### マネージャー実測

- `bin/rails db:test:prepare && bundle exec rspec`: **556 examples / 0 failures**、Line Coverage **98.87% (1053/1065)**。一次完了時 549 から +7（finding B/M/R/J の追加 spec）。
- `bin/rubocop`: **159 files inspected, no offenses detected**。
- `bin/brakeman --no-pager`: Errors 0 / Security Warnings 0。

### 反映確認（grep 実測）

- **A**: `password_needs_sync?` private + `@password_pending_sync` フラグ採用（`user.rb:31, 112, 123`）。`password=` setter でフラグを立て、`ensure` で確実に落とす。
- **B**: `oauth_identities.find_or_create_by!(provider:, uid:)` 2 箇所（`user.rb:73, 82`）。
- **C**: `find_or_create_for_oauth` 全体 `transaction do` 化（`user.rb:67`）。内側 `transaction` 削除。
- **D**: ENV を読むのは `config/initializers/omniauth.rb` の 2 箇所（provider 登録 + `Rails.configuration.x.sso_enabled` 計算）のみ。view（`sessions/new.html.erb:31`）と spec（`sso_spec.rb`）は `Rails.configuration.x.sso_enabled` を参照。
- **F**: routes は `post "/auth/:provider"` のみ（`config/routes.rb:20`）。GET 受けは削除。
- **I**: migration `down` 冒頭で `LEFT JOIN password_credentials` による OAuth 限定ユーザー検出 → `ActiveRecord::IrreversibleMigration` raise（`db/migrate/20260606000001_*.rb:31-38`）。
- **J**: `pc.password_confirmation = password_confirmation unless password_confirmation.nil?`（`user.rb:118`）。
- **M**: `return nil if normalized_email.blank?`（`user.rb:65`）。
- **R**: 仮想属性 `password = nil` のリセットを廃止し、`@password_pending_sync` フラグを `ensure` で必ず false 化（dirty tracking への副作用を回避）。
- **T**: `spec/system/sso_spec.rb` は ENV 直書きをやめ `Rails.configuration.x.sso_enabled` を before/after でトグル。

### マネージャー所見

- finding R は Coder が「削除のみ」「`after_commit` 移行」両案とも別問題（同一インスタンスで別 attribute を `update!` した際の二重 PC 保存）を解決しないと判断し、**`@password_pending_sync` フラグ + `ensure` 解除**の第3案を採用。dirty tracking 影響なし・二重保存なしを満たす。妥当な判断と評価。
- 機能要件の振る舞いは変えていない（Tester PASS した 549 例は同じ振る舞いで通過、追加 7 例も期待通り）。

## 動作確認（マネージャー側 grep / 実読のみ。手動 OAuth は ENV と Google Console 要のため Coder 報告に委任）

- 既存パスワードユーザーのログイン: Coder 報告で開発DBに `predev@example.com / secret123` を移行 → bcrypt 一致を確認、`db:rollback STEP=3` で `users.password_digest` 復元 → 再前進で安定。手動再現は本マネージャーセッションでは未実施。
- Google OAuth 実通信: 実 ENV/Console 設定が必要なため本フェーズで未実施。`spec/system/sso_spec.rb`（mock）と `spec/requests/auth/omniauth_callbacks_spec.rb`（成功/拒否/failure）で機能 PASS。

## 完了化

- `docs/tasks/00-overview.md` の 20 行ステータスを `✅完了` に更新
- `docs/tasks/PROGRESS_LOG.md` の 20 行を `✅完了 / Coder/Tester/Reviewer / [manager/20-sso.md]` に更新
- マイグレーション承認履歴の 20 行を `✅承認・実行済み` に更新
- ブランチ `feat/20-sso` は worktree 内に残置。PR 作成は**ユーザー指示時のみ**実施（本セッション内では未実施）。

## 最終実測値（再現済み）

| 指標 | 値 |
|---|---|
| `bundle exec rspec` | 556 examples / 0 failures |
| Line Coverage | 98.87% (1053/1065)、閾値 85% クリア |
| `bin/rubocop` | 159 files / no offenses |
| `bin/brakeman` | Errors 0 / Security Warnings 0 |
| `bin/bundler-audit` | No vulnerabilities found |
| `feat/20-sso` コミット数 | 7（feat 3 + refactor 3 + docs 1） |
