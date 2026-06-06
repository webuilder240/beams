# ADR 0002: Active Record Encryption を撤廃し SA 鍵を平文保存する

- **Status**: Accepted
- **Date**: 2026-06-06
- **Deciders**: ボス / マネージャー / Coder
- **Related**: トピック [`docs/tasks/27-drop-ar-encryption.md`](../tasks/27-drop-ar-encryption.md)、進捗ログ [`docs/tasks/progress/27-drop-ar-encryption.md`](../tasks/progress/27-drop-ar-encryption.md)、対象モデル `Bigquery::Connection`（`app/models/bigquery/connection.rb`）、関連トピック [`docs/tasks/26-once-platform.md`](../tasks/26-once-platform.md)（ONCE プラットフォーム採用）

---

## Context

Beams は ONCE プラットフォーム（[basecamp/once](https://github.com/basecamp/once)）で配布する単一 Docker コンテナ型の BI ツール（[docs/PRODUCT_PLAN.md §2](../PRODUCT_PLAN.md)）。トピック26 で配布層を basecamp/once に置き換えた結果、運用者の UX 上のフリクションとして次の構造が残っていた:

- Beams は `config/credentials.yml.enc` を持つ。中身は (1) `secret_key_base` と (2) Active Record Encryption の 3 鍵（`active_record_encryption.{primary_key,deterministic_key,key_derivation_salt}`）のみ。
- このうち (1) `secret_key_base` は ONCE が `SECRET_KEY_BASE` env を自動生成・永続化するため不要。
- (2) Active Record Encryption の 3 鍵は `Bigquery::Connection#service_account_json` を暗号化するためだけに使われている。
- credentials を復号するために `RAILS_MASTER_KEY`（= `config/master.key` の値）を ONCE custom env で **必須**として渡さねばならず、ONCE TUI / CLI の「1 行設置」UX を損なう（[docs/tasks/26-once-platform.md](../tasks/26-once-platform.md) の B グループで一旦は許容）。

Beams の脅威モデルを改めて整理すると:

- 配布形態は **自社サーバー設置**（買い切り・ONCE が管理するホスト 1 台）であり、攻撃面は「ホスト侵入」と「`/storage` ボリューム取得（ディスク／バックアップ流出）」に集約される。
- `/storage` 配下の SQLite ファイル本体に攻撃者がアクセスできる状況では、AR Encryption のキー素材も同じホスト env（`RAILS_MASTER_KEY`）から取り出せるため、**アプリ層暗号化は実効防御にならない**（環境変数または Rails プロセスメモリから鍵が読める）。
- 一方、ONCE 経由の自動バックアップ（`/hooks/pre-backup` で書き出すスナップショット）と手動 `rake beams:backup` の出力 `*.sqlite3.gz` は SQLite ダンプを gzip 圧縮しただけで暗号化していない。よって AR Encryption の有無にかかわらず **バックアップ転送経路の暗号化（ONCE 側 TLS / SSE）に SA 鍵保護を依存させる必要がある**。

つまり「アプリ層 AR Encryption を維持しても脅威モデル上の追加防御は薄く、運用 UX を犠牲にしている」という非対称な状態だった。

---

## Decision

**Active Record Encryption を撤廃する。** `Bigquery::Connection#service_account_json` は SQLite に **平文**で保存する。

- `app/models/bigquery/connection.rb` から `encrypts :service_account_json` を削除する。`service_account_json` のカラム型（`text`）は維持し、マイグレーションは行わない。
- `config/environments/test.rb` の `config.active_record.encryption.{primary_key,deterministic_key,key_derivation_salt}` 3 行を削除する。
- `config/credentials.yml.enc` を git から削除する。`config/master.key` は元々 git 管理外（`.gitignore` 済み）のため作業対象は worktree ローカルファイルの削除のみ。
- `Dockerfile` / `bin/boot` / `bin/docker-entrypoint` から `RAILS_MASTER_KEY` 前提のコメント・ENV 記述を撤去する。`SECRET_KEY_BASE_DUMMY=1` での `assets:precompile` 段はそのまま維持する（Rails の precompile 要件であり credentials 復号には関係しない）。
- 既存暗号化データの移行は不要。Beams は本変更の時点で稼働中インスタンスを持たないため、稼働データのリパース・再暗号化を考慮しない。test 環境は `bin/rails db:test:prepare` で再構築される。

SA 鍵の保護は次の **ホスト側保護**に委ねる（[docs/INSTALL.md §3 セキュリティ上の注意](../INSTALL.md)）:

1. ホストディスクの暗号化（LUKS など）
2. `/var/lib/docker/volumes/...`（ONCE の `/storage` 実体）の root 以外への遮断。Beams コンテナは非 root（`uid 1000` rails ユーザー）で動作する。
3. バックアップ転送経路の暗号化（ONCE 側 TLS / SSE）
4. BigQuery 側で SA に与える権限の最小化（漏洩時の被害局所化）

---

## Alternatives Considered（代替案と却下理由）

### 1. Active Record Encryption を維持し、`RAILS_MASTER_KEY` を必須として運用する

**却下理由**:

- 脅威モデル上、`RAILS_MASTER_KEY` と SQLite ファイルは同じホスト上に同居する。`/storage` ボリュームを盗める攻撃者は ONCE custom env（プロセス env または ONCE の設定ファイル）から `RAILS_MASTER_KEY` も取得でき、AR Encryption は実効防御にならない。
- ONCE TUI / CLI の 1 コマンド設置 UX を阻害する（毎回 `--env RAILS_MASTER_KEY=...` または TUI で行追加が必要）。
- credentials.yml.enc の中身は AR Encryption 3 鍵だけになっており、`secret_key_base` は ONCE 側 env で代替される。アプリ層暗号化のためだけに `RAILS_MASTER_KEY` を必須に据えるのは非対称。

### 2. SA 鍵を envelope encryption（KMS 等）で別管理する

却下。Beams は自社サーバー設置（ONCE）配布で、外部 KMS（AWS KMS / GCP KMS 等）への依存を増やすと「単一コンテナで動く」配布形態を崩す。脅威モデル（ホスト盗難・バックアップ流出）に対しても、KMS への認証情報自体を同じホストに置く必要がありキー入れ替え問題が再帰する。

### 3. SA 鍵を別の SQLite ファイル + 別パーミッションで保存する

却下。`/storage` ボリュームが侵害されたら同じファイルシステム上にあるため意味がない。`production.sqlite3` 内の 1 カラムを別ファイルに分けても、Beams プロセス自身が両者にアクセスできる必要があるため攻撃面は変わらない。

### 4. 平文保存 + アプリ側でフィールド単位ハッシュ化（伸長後比較不能）

却下。SA 鍵は復号して BigQuery に渡す必要があるため、ハッシュ（一方向）にはできない（用途が認証ではなく秘匿クライアント資格情報）。

---

## Consequences

### Positive

- **`RAILS_MASTER_KEY` 不要**。ONCE TUI / CLI で `once install --image ghcr.io/webuilder240/beams:latest` だけで完結する。custom env の入力は撤廃される（`BUGSNAG_API_KEY` 等の任意 env のみ残る）。
- `config/credentials.yml.enc` / `config/master.key` を完全に廃止。`rails credentials:edit` の運用フロー不要。
- test 環境の AR Encryption ダミー鍵設定（`config/environments/test.rb` の 3 行）を撤去でき、CI も `RAILS_MASTER_KEY` を渡す必要がなくなる（既に不要ではあったが、コードベース側の整合性が改善）。
- Dockerfile / INSTALL.md / README.md / PRODUCT_PLAN.md の説明が単純化される（運用ドキュメントの行数削減）。

### Negative / 留意点

- **SA 鍵は SQLite に平文で保存される**。`/storage/production.sqlite3` の `bigquery_connections.service_account_json` text カラムをそのまま読めば SA 鍵が取得できる。
- **バックアップファイル（`/storage/backups/*.sqlite3.gz`）も平文**。ONCE 経由の自動バックアップ・手動 `rake beams:backup` の出力ともに SQLite ダンプの gzip 圧縮のみで暗号化していない。バックアップを外部（S3 等）に転送する場合は ONCE 側で TLS / SSE を必ず有効化する。
- ホスト側のディスク暗号化・ファイルパーミッション・バックアップ転送経路の暗号化が**運用上の必須前提**になる。[docs/INSTALL.md §3 セキュリティ上の注意](../INSTALL.md) に明記し、運用者の責務として周知する。
- 将来、複数組織での SaaS 提供等で脅威モデルが変わる場合は本 ADR を再評価する。その時点では envelope encryption + KMS 連携が選択肢となる。

### Migration（既存稼働インスタンスへの影響）

- 本変更時点で稼働中インスタンスは無い（ボス確認済み）。よって既存暗号化済みデータの復号 → 平文書き直し作業は行わない。
- 仮に将来「既に AR Encryption で暗号化された `service_account_json` を持つ DB」をリストアしたい場合は、本コミットを巻き戻すか、旧 `RAILS_MASTER_KEY` を一時的に与えてアプリ起動 → SA 鍵を平文で再保存する移行スクリプトが別途必要になる。本 ADR ではそのスクリプトを用意しない。
