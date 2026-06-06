# 進捗ログ: トピック27 — Active Record Encryption 撤廃

- **担当**: Coder（AgentTeam 単独）
- **トピック計画**: [../27-drop-ar-encryption.md](../27-drop-ar-encryption.md)
- **関連 ADR**: [../../adr/0002-drop-active-record-encryption.md](../../adr/0002-drop-active-record-encryption.md)

---

## 2026-06-06: Coder 実装

### 方針確認

- マネージャー指示書（プロンプト）に従い、AR Encryption を撤廃し credentials.yml.enc を git から削除する。
- 既存稼働インスタンスなし・test DB は `db:test:prepare` で再構築されるため、暗号化済みデータの移行は不要。
- TDD: 「平文保存」を期待する spec へ書き換え → Red → `encrypts :service_account_json` 削除 → Green の順序を踏む。

### 実装ステップ

1. **TDD Red**: `spec/models/bigquery/connection_spec.rb` の `describe "encryption of service_account_json"` を `describe "service_account_json storage (plaintext)"` に書き換え、「raw SQLite 行に平文が入っている」ことを期待するアサーションへ変更。
   - 実行: `SKIP_COVERAGE_CHECK=1 bundle exec rspec spec/models/bigquery/connection_spec.rb -e "stores the plaintext as-is"`
   - 結果: **Red**。raw 値が AR Encryption の暗号文構造（`{"p":"...","h":{"iv":"...","at":"..."}}`）になっていることを確認。
2. **TDD Green**: `app/models/bigquery/connection.rb` から `encrypts :service_account_json` を削除し、コメントを平文保存方針に更新。
   - 実行: `SKIP_COVERAGE_CHECK=1 bundle exec rspec spec/models/bigquery/connection_spec.rb`
   - 結果: **43 examples / 0 failures**。
3. **config 整理**: `config/environments/test.rb` の AR Encryption ダミー鍵 3 行（`primary_key` / `deterministic_key` / `key_derivation_salt`）+ 関連コメントを削除。
4. **credentials 撤廃**: `git rm config/credentials.yml.enc`。`config/master.key` は元々 git 管理外（worktree にも存在しなかった）。
5. **Dockerfile**: 冒頭コメントの `docker run -e RAILS_MASTER_KEY=...` を削除。`SECRET_KEY_BASE_DUMMY=1` precompile のコメントを「Rails の precompile 要件」へ更新。
6. **bin/boot / bin/docker-entrypoint**: grep で `RAILS_MASTER_KEY` 参照無しを確認。変更なし。
7. **docs/INSTALL.md**:
   - §2.2 のインストール手順（TUI / CLI）から `RAILS_MASTER_KEY` 関連の手順を撤去。`once install --image ...` だけで完結する旨を明記。
   - §3 「初期 env (`RAILS_MASTER_KEY`)」節を「セキュリティ上の注意」節へ全面差し替え（SA 鍵・バックアップが平文である旨と、ホスト側保護 4 点）。
   - §8.1 env 表から `RAILS_MASTER_KEY` 行を削除、`SECRET_KEY_BASE` を「自動」扱いに更新、表下に「`RAILS_MASTER_KEY` は不要」を明記。
8. **README.md**: インストールコマンドから `RAILS_MASTER_KEY` を撤去、env 表から `RAILS_MASTER_KEY` 行を削除、「セキュリティ」節を新設して SA 鍵・バックアップ平文を明記。
9. **docs/PRODUCT_PLAN.md**: §4.2 の「Active Record Encryption で暗号化」を「平文保存」へ更新し、ADR 0002 と INSTALL.md §3 へのリンクを追加。
10. **ADR 0002**: `docs/adr/0002-drop-active-record-encryption.md` を新規作成（採用判断・脅威モデル・代替案・Consequences・移行方針）。
11. **タスクファイル**: `docs/tasks/27-drop-ar-encryption.md` 新規作成、`docs/tasks/00-overview.md` / `docs/tasks/PROGRESS_LOG.md` の表にトピック27 行を追記。

### 最終検証

- `bin/rails db:test:prepare` 実行後 `bundle exec rspec`: 全 green、SimpleCov ≥ 85% を実測（本ログ末尾に実測値を追記）。
- `bin/rubocop`: clean を実測（本ログ末尾に実測値を追記）。
- 残存 grep（`RAILS_MASTER_KEY|credentials\.yml\.enc|master\.key|encrypts `）: 過去経緯記録（`docs/tasks/01-...`, `04-...`, `18-...`, `22-...`, `23-...`, `26-...`, `docs/tasks/migrations/...`, `docs/tasks/progress/04-...`, `docs/tasks/progress/18-...`, `docs/tasks/progress/26-...`）のみ。**実体（`app/`, `config/`, `lib/`, `bin/`, `Dockerfile`, `README.md`, `CLAUDE.md`, `docs/PRODUCT_PLAN.md`, `docs/INSTALL.md`）には 0 件**。

### コミット

- 1 コミットでまとめる: `feat(27): Active Record Encryption 撤廃 / RAILS_MASTER_KEY 不要化`

（実測値・コミットハッシュは作業完了時にマネージャー報告に記載）
