# ADR 0002: 認証方式の identity テーブル分離（`users` から `password_digest` を分離する）

- **Status**: Accepted
- **Date**: 2026-06-06
- **Deciders**: ボス / マネージャー / Coder
- **Related**: トピック `docs/tasks/20-sso.md`、マイグレーション資料 `docs/tasks/migrations/20-users-oauth-migration.md`、進捗ログ `docs/tasks/progress/20-sso.md`、対象モデル `User`・`PasswordCredential`・`OauthIdentity`

---

## Context

[[03-auth-users]] で導入した自前メール+パスワード認証は `users.password_digest` を直接 `has_secure_password` で扱う最小構成だった。トピック20（[[20-sso]]）では Google OAuth ログインを共存させる。

候補のスキーマは次の 2 系統があった:

1. **`users` テーブルに認証方式カラムを追加する案**
   - 例: `users` に `provider`・`uid`・`password_digest` を持たせる
   - 将来 Microsoft / Slack 等が増えるたびに `users` のスキーマを変更する必要がある
   - 1 ユーザーが複数 OAuth プロバイダにリンクする要求が出た瞬間に 1 対多テーブルへの移行が必要になる
   - `users` テーブルが「人」と「認証手段」の両方を抱え、責務が混ざる
2. **identity テーブルに分離する案（採用）**
   - `users` は「人」（email, role）のみ
   - パスワード認証 → `password_credentials`（1 対 1、`has_secure_password` をこちらに置く）
   - OAuth → `oauth_identities`（1 対多、`(provider, uid)` ユニーク）

## Decision

**`users` テーブルには認証方式（password/oauth）カラムを増やさない**。パスワード認証と OAuth 認証はそれぞれ専用の identity テーブル（`password_credentials` / `oauth_identities`）に分離する。

- `users` カラムは `id`, `email`, `role`, `created_at`, `updated_at` のみ
- `User has_one :password_credential`、`User has_many :oauth_identities`
- 既存の `User#password=` / `User#authenticate` 等の呼び出し（`SessionsController`, `SetupWizardController`, `Admin::UsersController`）を壊さないため、`User` は **仮想属性 + 委譲**で同じ外部 API を提供する
- `User.find_or_create_for_oauth(provider:, uid:, email:)` クラスメソッドで OAuth コールバック側の解決ロジックを集約する（4 分岐: 既存 identity / email 突合 / 自動作成 / 拒否）

## Consequences

### 良い点

- `users` テーブルが「人」だけを表現するクリーンな状態を維持できる
- 将来 Microsoft / Slack を追加するときに `oauth_identities` に provider を増やすだけで対応でき、`users` スキーマは無変更
- パスワード認証と OAuth を 1 ユーザーが併用可能（B4-A: 同 email の既存ユーザーに `oauth_identities` 行を追加してリンク）
- 既存ユーザーは同じパスワードで引き続きログインできる（マイグレーション内で `users.password_digest` を `password_credentials` に全件コピー）

### 悪い点・トレードオフ

- テーブル数が増える（`password_credentials` + `oauth_identities` の 2 つ）
- `User` に仮想属性 + 委譲メソッドが乗るため、認証 API の実装が `User` 単独で完結せず `PasswordCredential` を併せて見る必要がある
- `users.password_digest` を削除する破壊的マイグレーションが必要（既存 DB は事前バックアップ必須）
- `down` は `password_credentials` を持たない（= OAuth 限定）ユーザーが存在すると `NOT NULL` 復元で失敗する。`down` 実行時はそれらを事前整理する運用が必要

## 補足

- `User#authenticate` は `password_credential` が無ければ `false` を返す（B9-A）。これにより OAuth 限定ユーザーは仮にメール+パスワードフォームへ来ても認証されない
- `ApplicationSetting#allowed_email_domain` を空にすると未登録 email の自動プロビジョニングは行われない（拒否される）。明示設定がない限り「誰でも入れる」状態にならない安全側のデフォルト
- 詳細は `docs/tasks/20-sso.md` のボス決定事項（B1〜B9）参照
