# トピック27: Active Record Encryption 撤廃（`RAILS_MASTER_KEY` / `credentials.yml.enc` 撤去）

- **ステータス**: 進行中
- **依存**: トピック [26 ONCE プラットフォーム移行](26-once-platform.md)（basecamp/once 採用済み）
- **関連 ADR**: [docs/adr/0002-drop-active-record-encryption.md](../adr/0002-drop-active-record-encryption.md)
- **計画書**: [docs/PRODUCT_PLAN.md §4.2 BigQuery接続](../PRODUCT_PLAN.md)

---

## 背景・ゴール

ONCE プラットフォーム配布で `RAILS_MASTER_KEY` を必須にするのは UX が悪い。`config/credentials.yml.enc` の中身は ①`secret_key_base`（ONCE が `SECRET_KEY_BASE` env で自動生成・永続化するので不要）と ②`active_record_encryption.{primary_key,deterministic_key,key_derivation_salt}` 3 鍵（AR Encryption 用）の 2 つだけ。**AR Encryption を撤廃すれば credentials.yml.enc ごと撤廃でき、`master.key`/`RAILS_MASTER_KEY` も完全に不要になる**。

設計判断はマネージャー〜ボスで合意済み: BigQuery サービスアカウント JSON は SQLite に**平文**で保存し、保護はファイルパーミッション・ホスト側ディスク暗号化・`/storage` ボリュームへのアクセス制御に委ねる。バックアップファイル（`/storage/backups/*.sqlite3.gz`）も平文。詳細は [ADR 0002](../adr/0002-drop-active-record-encryption.md) を参照。

---

## 受け入れ条件

- `bundle exec rspec` で全テスト green、SimpleCov カバレッジ 85% 以上を維持。
- `bin/rubocop` clean。
- `git grep -E 'RAILS_MASTER_KEY|credentials\.yml\.enc|master\.key|encrypts '` がコードベース実体に残らない（`docs/tasks/` 配下の過去経緯記録のみ残してよい）。
- ONCE TUI / CLI で `RAILS_MASTER_KEY` を渡さなくても Beams が `bin/boot` 通過する（既にトピック26 でコード上は確認済み）。

---

## チェックリスト

### 1. `Bigquery::Connection` から AR Encryption 撤廃

- [x] `spec/models/bigquery/connection_spec.rb` の「encryption of service_account_json」を「service_account_json storage (plaintext)」へ書き換え（平文保存を期待）。Red→Green→Refactor の TDD 順序。
- [x] `app/models/bigquery/connection.rb` から `encrypts :service_account_json` を削除。SA 鍵保存方針のコメントを更新。
- [x] カラム自体（`service_account_json` text）はそのまま維持。マイグレーション不要。

### 2. `config/credentials.yml.enc` / `config/master.key` を git から削除

- [x] `git rm config/credentials.yml.enc`
- [x] `config/master.key` は `.gitignore` 済みで git 管理外。worktree ローカルファイルが残れば削除（コミットには含まれない）。
- [x] 再生成防止: 何もしない（`rails credentials:edit` を実行しない運用、と INSTALL.md / ADR に明記）。

### 3. `config/environments/test.rb` の AR Encryption 設定削除

- [x] `config.active_record.encryption.primary_key` / `deterministic_key` / `key_derivation_salt` の 3 行とコメントを削除。
- [x] `encrypts` を使うモデルが残っていないことを確認（1 で削除済み）。

### 4. `Dockerfile` / `bin/boot` の `RAILS_MASTER_KEY` 前提を掃除

- [x] `Dockerfile` 冒頭コメント `docker run -d -p 80:80 -e RAILS_MASTER_KEY=...` の行を削除。
- [x] `bin/boot` / `bin/docker-entrypoint` を grep して `RAILS_MASTER_KEY` 検証・warning を確認（実体無し）。
- [x] `SECRET_KEY_BASE_DUMMY=1` の precompile はそのまま維持（コメントを「Rails の precompile 要件」へ更新）。

### 5. `docs/INSTALL.md` から `RAILS_MASTER_KEY` 節を撤去・簡素化

- [x] §3「初期 env (`RAILS_MASTER_KEY`)」節を削除。
- [x] インストール手順（TUI / CLI）から `--env RAILS_MASTER_KEY=...` を削除。`once install --image ...` だけで完結すると明記。
- [x] §8.1 「Beams が利用する env」表から `RAILS_MASTER_KEY` 行を削除。`SECRET_KEY_BASE` を「自動」扱いに更新。
- [x] §8.2 ONCE 由来未使用 env はそのまま維持（VAPID_*/SMTP_*/NUM_CPUS）。
- [x] 新規節「セキュリティ上の注意」を §3 として追加（SA 鍵・バックアップ平文・保護策 4 点）。

### 6. `docs/PRODUCT_PLAN.md` / `CLAUDE.md` の整合

- [x] PRODUCT_PLAN.md §4.2 の「Active Record Encryption で暗号化」記述を「平文保存」へ更新。
- [x] CLAUDE.md は `RAILS_MASTER_KEY` / credentials / encrypts への言及なし（grep で確認）。
- [x] ADR 0002 を `docs/adr/0002-drop-active-record-encryption.md` に作成（採用判断・代替案・リスク・代替保護策）。

### 7. 関連 spec の整理

- [x] `spec/models/bigquery/connection_spec.rb` の暗号化検証を平文保存検証に書き換え。
- [x] `spec/support/` 配下に AR Encryption 関連 setup なし（grep で確認）。
- [x] `bundle exec rspec` で全 green、SimpleCov 85%+ を実測確認。

### 8. README.md の整合

- [x] `RAILS_MASTER_KEY` 記述を削除。「環境変数」表から削除。「セキュリティ」節を新設して SA 鍵・バックアップ平文を明記。

### 9. 進捗・索引の更新

- [x] `docs/tasks/00-overview.md` の表にトピック27 を追記。
- [x] `docs/tasks/PROGRESS_LOG.md` の表にトピック27 を追記。
- [x] `docs/tasks/progress/27-drop-ar-encryption.md` に時系列ログを記録。
