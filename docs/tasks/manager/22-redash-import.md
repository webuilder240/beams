# マネージャー管理ログ — トピック22: Redash クエリ取り込み（API版）

> Coder の実装ログ（`docs/tasks/progress/22-redash-import.md`）とは別の、マネージャーによる管理・実測検証ログ。偽の数値・ハッシュは書かない。

- **タスク定義**: [docs/tasks/22-redash-import.md](../22-redash-import.md)
- **マイグレーション資料**: [docs/tasks/migrations/22-redash-sources-migration.md](../migrations/22-redash-sources-migration.md)
- **ブランチ**: `feat/22-redash-import`（worktree `.claude/worktrees/feat-22-redash-import` で Coder 作業）
- **体制**: マネージャー1 / Coder 1 / Tester 1 / Reviewer 1

## ボス決定事項（2026-06-06 確定済み、API版に変更）

| ID | 決定 |
|---|---|
| B1 | Redash 公式 REST API（`/api/queries`、`/api/queries/:id`、`Authorization: Key`） |
| B2 | `RedashSource`（URL + 暗号化APIキー + 名前）、AR Encryption |
| B3 | クエリ一覧で複数選択して一括取り込み |
| B4 | 未対応 type は警告付き string フォールバック |
| B5 | 所有者=ログインユーザー、BQ 接続=必須選択、`data_source_id` 無視 |
| B6 | `queries.imported_from` カラム追加なし |
| B7 | Redash 拡張記法は警告のみ、SQL 本文はそのまま保存 |
| B8 | SSRF 基本ガード（HTTPS強制 / private/loopback/metadata ブロック / 5s timeout / リダイレクト追従なし） |

## マイグレーション承認（2026-06-06、`/agent-team` 着手時）

ボス承認: **`redash_sources` テーブル新規（非破壊）**。`docs/tasks/migrations/22-redash-sources-migration.md` の内容どおり、`name` unique index・`api_key` text NOT NULL（AR Encryption で透過暗号化）。

## 基線（着手前の実測、main `a549b76` 時点）

- `bundle exec rspec`: 513 examples / 0 failures、Line Coverage 98.88%
- `bin/rubocop`: 147 files / no offenses

## 実行サイクル記録

| グループ | 内容 | 状態 | マネージャー実測 |
|---|---|:---:|---|
| 全体 | webmock / migration / RedashSource / RedashClient / RedashQueryPayload / admin CRUD / インポート / ビュー / spec / docs | ✅Coder完了・マネージャー検証済 | 下記 |
| リファクタ | Reviewer 指摘 must + 主要 should | ✅Coder完了・マネージャー検証済 | 下記 |

## マネージャー実測検証（Coder 一次完了後、2026-06-06）

### コミット実在（`git cat-file -t` 確認済）

- `7182af1` feat: gem webmock 追加 + 初期化
- `97f7e65` feat: redash_sources マイグレーション
- `1edd31d` feat: RedashSource モデル + 暗号化 + SSRF 共通ガード
- `b8bbb8f` feat: RedashClient PORO + SSRF ガード + WebMock スペック
- `18abc1d` feat: RedashQueryPayload PORO
- `4a5ffe2` feat: admin/redash_sources CRUD + ビュー
- `298ed8a` feat: RedashImportsController + ビュー + クエリ一覧リンク
- `09903d4` feat: System Spec + ドキュメント更新

### 実測値

- `bundle exec rspec`: **585 examples / 0 failures**（基線 513 → +72）
- Line Coverage: **98.01% (1182/1206)**、閾値 85% クリア
- `bin/rubocop`: 160 files / no offenses
- `bin/brakeman`: Errors 0 / Security Warnings 0
- `bin/bundler-audit`: No vulnerabilities found

### 要件外/逆実装チェック

- `app/services/` 不在・`*Service` 命名なし
- 全 PORO（`redash_source.rb` / `redash_client.rb` / `redash_query_payload.rb`）は `app/models/` 配下
- `db/schema.rb` に `redash_sources`（name unique index、`api_key text not null`）反映
- `RedashSource.encrypts :api_key`（`Bigquery::Connection.service_account_json` と同パターン）
- `RedashClient` の例外 5種（Unauthorized / NotFound / ServerError / Timeout / ForbiddenURLError）
- `spec/rails_helper.rb` で `WebMock.disable_net_connect!(allow_localhost: true)`

## Tester QA 結果（2026-06-06）

- 受け入れ条件 17 項目すべて **PASS**（ゴール / タスク / 動作確認）
- ボス決定 B1〜B8 すべて反映
- **総合判定: PASS**

## Reviewer レビュー結果（2026-06-06）

`reviewer` 観点で **must 3件 / should 5件 / nice-to-have 6件**:

| ID | 重要度 | 概要 |
|---|---|---|
| M1 | must | SSRF ガードに DNS rebinding TOCTOU（`guard_url!` と `Net::HTTP` の DNS 再解決の間でアドレス差し替えが可能） |
| M2 | must | `import_one` が `Integer(id)` の `ArgumentError` を rescue せず、不正 ID 1 件でループ中断 |
| M3 | must | `RedashSource → RedashClient::ForbiddenURLError` の逆依存 |
| S1 | should | IPv6 リテラル URL が「解決失敗」で偶然弾かれている |
| S2 | should | `apply_parameter_types` が SQL 本文に出現しないパラメータの型情報を黙って捨てる |
| S3 | should | 将来テナント時の IDOR 考慮（TODO） |
| S4 | should | フラッシュに内部 IP / 例外 body が露出 |
| S5 | should | `RedashSource.url` の既存クエリパラメータが API 呼び出しに残留（トークン漏えい経路） |
| N1〜N6 | nice-to-have | （見送り） |

### ボス判断（2026-06-06）

- **must + 主要 should 適用**: M1, M2, M3, S1, S2, S4, S5
- S3 / nice-to-have 全件 **見送り**（理由: 現状未影響・テナント機能は将来課題）

## Coder リファクタ対応・マネージャー再検証（2026-06-06）

### 追加コミット（実在確認済）

- `4de3c2a` refactor(22-redash-import): SSRF DNS rebinding 対策と IP リテラル衛生化 (M1,S1,M3)
- `deb9797` fix(22-redash-import): import_one の rescue 漏れ修正と内部情報のフラッシュ漏れ抑止 (M2,S2,S4)
- `2213b0e` docs(22-redash-import): Reviewer 指摘リファクタ対応セクションを追記

### マネージャー実測

- `bin/rails db:test:prepare && bundle exec rspec`: **599 examples / 0 failures**、Line Coverage **97.53% (1225/1256)**。一次完了時 585 から +14（DNS rebinding テスト / IPv6 リテラル / 型情報 warning / フラッシュ固定文言 / URL クエリ衛生化 / `query_ids` 混在）。
- カバレッジは 98.01% から 97.53% へわずかに低下（新規ガード経路の一部が rescue 内に集中したため）。85% 閾値は十分にクリア。
- `bin/rubocop`: 160 files / no offenses
- `bin/brakeman`: Errors 0 / Security Warnings 0
- `bin/bundler-audit`: No vulnerabilities

### 反映確認（grep 実測）

- **M1**: `RedashSource::GuardedTarget(uri:, ip:)` Struct（`redash_source.rb:22`）。`RedashClient#perform` で `Net::HTTP.new(uri.hostname, uri.port)` + `http.ipaddr = target.ip if http.respond_to?(:ipaddr=)`（`redash_client.rb:92-93`）。SNI / Host / 証明書検証は `uri.hostname` で維持し、TCP 接続先のみガード時の IP に固定。古い `net-http` には `respond_to?` で fallback。
- **M3**: `RedashSource::ForbiddenURLError` を権威化。`RedashClient::ForbiddenURLError = RedashSource::ForbiddenURLError` の alias で後方互換維持（`redash_client.rb:37`）。既存テストの参照を保つ。
- **S1**: `uri.hostname` 使用、`IPAddr.new(hostname)` が成功するなら DNS を介さず直接 `FORBIDDEN_RANGES` に照合（IPv6 リテラル `[::1]` 等を正しく範囲チェックで弾く）。
- **M2**: `RedashImportsController#import_one` 冒頭で `Integer(id, 10)` + `rescue ArgumentError`、最終 `rescue StandardError => e` で全例外を `ImportResult :failure` に変換。混在入力テストが追加されている。
- **S2**: `apply_parameter_types` が SQL 本文に出現しないパラメータを `ImportResult` の `:warning` 配列に積み、結果画面に表示。`Query#sync_parameters!` は触らず B7 方針と整合。
- **S4**: 各 rescue で固定文言、`Rails.logger.warn(...)` で詳細を記録（`redash_imports_controller.rb:170`）。内部 IP / 例外 body はフラッシュに出ない。
- **S5**: `RedashClient#build_url` で `base.query = nil` をクリアしてから `URI.encode_www_form(query_params)` を当てる（`redash_client.rb:79-80`）。`url: ".../?leak=token"` のトークン漏えい経路を遮断。

### マネージャー所見

- M1 の実装方針（`http.ipaddr=` を使い hostname は名前のまま渡す）は **TLS の SNI / 証明書 hostname 検証を壊さない最小修正**で適切。`Net::HTTP` の Ruby バージョン差は `respond_to?(:ipaddr=)` で defensive にハンドルされている。
- カバレッジ低下は新規防御コードの一部だが、新規 spec 14 件で主要ガード経路を検証済。
- S5 のコミット境界（M1 と同梱）は許容範囲。progress ログでマッピングを明示。

## 動作確認（自動テスト主体）

実 Redash サーバへの結合検証は本セッションでは未実施（ユーザー判断）。WebMock 全スタブ + `disable_net_connect!` で実 HTTP が一切発火しないことを確認済。

## 完了化

- `docs/tasks/00-overview.md` の 22 行ステータスを `✅完了` に更新
- `docs/tasks/PROGRESS_LOG.md` の 22 行を `✅完了 / Coder/Tester/Reviewer / manager/22-redash-import.md` に更新
- マイグレーション承認履歴の 22 行を `✅承認・実行済み` に更新

## 最終実測値（再現済み）

| 指標 | 値 |
|---|---|
| `bundle exec rspec` | 599 examples / 0 failures |
| Line Coverage | 97.53% (1225/1256)、閾値 85% クリア |
| `bin/rubocop` | 160 files / no offenses |
| `bin/brakeman` | Errors 0 / Security Warnings 0 |
| `bin/bundler-audit` | No vulnerabilities found |
| `feat/22-redash-import` コミット数 | 11（feat 8 + refactor 1 + fix 1 + docs 1） |
