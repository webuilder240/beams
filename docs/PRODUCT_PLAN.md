# Beams — サービス計画書

> BigQuery専用の、SQLファーストなセルフホスト型BIツール。
> Redashの思想を継承し、その弱点を克服する「後継」。

- **ステータス**: ドラフト（初版）
- **最終更新**: 2026-05-31
- **対象読者**: 開発チーム / 意思決定者

---

## 1. ポジショニング

### 1.1 何を作るのか

Beamsは、**SQLを書ける人がクエリを作り、結果を可視化し、組織内で共有する**ためのBIツールである。Redashが切り拓いた「SQLファースト＋セルフホスト」という思想を継承しつつ、Redashが抱えた弱点を明確に克服することを狙う。

### 1.2 「後継」の定義

「後継」とは**機能・データの互換ではなく、思想の継承**を指す。

| 観点 | Redash | Beams |
|------|--------|-------|
| 思想 | SQLファースト・セルフホスト | **継承** |
| メンテナンス | 停滞 | モダンスタックで再構築 |
| コスト管理 | 無頓着（事故が起きる） | **dry-run表示＋上限ガードを標準装備** |
| 対応データソース | 多数（抽象化レイヤが複雑） | **BigQueryのみに集中** |
| インフラ | Postgres + Redis + 複数プロセス | **SQLite単一アプライアンス（ONCE）** |

### 1.3 ターゲット

**単一組織が自社サーバーに導入して社内で使う**ケース（セルフホスト）。新規にBIを導入する組織を主対象とする。既存Redashからの移行は初期スコープ外（→ §7 ロードマップ）。

### 1.4 中心軸（差別化）

1. **BigQuery専用に振り切る** — データソース抽象化を作らず、BigQueryならではの体験（スキーマ探索・コスト見積もり）に開発資源を集中。
2. **コスト保護を標準装備** — Redash最大の弱点。「気づける（dry-run）＋止められる（上限ガード）」を最初から。
3. **ONCEによる買い切り・単一アプライアンス** — 外部依存ゼロ、curl一発インストール、自動アップデート・自動バックアップ。

---

## 2. 配布形態（ONCE）

[37signalsのONCE](https://github.com/basecamp/once) で配布する。買い切り・自社サーバーに単一Dockerコンテナで一発インストールする形態。

配布レイヤは `basecamp/once` プラットフォームに統合する（旧自前配布層――自前 `install.sh` は撤去、自前 systemd 自動アップデート層・自前 TLS 設定なども含めトピック 26 で全撤去）。インストール・自動アップデート・バックアップは ONCE が担当し、Beams 側はコンテナ起動時の DB 初期化と pre-backup フック（`bin/hooks/pre-backup` / `Beams::Once::PreBackup`）だけを提供する。TLS 終端は ONCE プラットフォーム側に委ね、Beams コンテナは **HTTP 80 のみ**を公開する。手順は [docs/INSTALL.md](INSTALL.md)。

### 2.1 ONCEのアプリ側要件

- 単一Dockerコンテナ
- HTTP を **port 80** で待受
- **`/up`** ヘルスチェックエンドポイント（Rails 8標準）
- 永続データは **すべて `/storage` 配下**（ONCEがファイル単位で自動バックアップ）
- 外部サービス依存なし

### 2.2 プロセス管理（once-campfireに倣う）

[once-campfire](https://github.com/basecamp/once-campfire) の構成を**翻訳して**採用する。Campfireは時期的にSolid Stack以前でRedis + Resqueを使うため、そこをSolid Stackに置換する。

- **`Dockerfile` の `CMD` は `bin/boot` 一発**。
- **`bin/boot` は自前の極小スーパーバイザ**（Campfireの約50行のRubyをほぼ流用）。`Procfile`を読み、各プロセスを `Process.spawn` で起動、`INT/TERM/CLD` をトラップして子に伝播、全プロセスを `wait` する。foreman等の外部依存を増やさない（ONCE思想）。
- **`web` は Thruster（`thrust`）で Puma をラップ**。Thruster が HTTP（h2c も可）・port 80 待受・静的アセット配信・X-Sendfile（CSVダウンロード）を担当する。TLS 終端は ONCE プラットフォーム側に委ねるため、Beams コンテナ自体は HTTP 80 のみ公開する。

```
# Procfile（Solid Stack版 — Campfireのredis/resqueを置換）
web:    bundle exec thrust bin/rails server
worker: bundle exec bin/jobs          # SolidQueue（別プロセス）
```

- **workerは別プロセス**にする。BigQuery待ちジョブのスレッド数を、Pumaのリクエストスレッドと独立にサイズするため（→ §6.2）。
- **起動時マイグレーション**: ONCEは自動アップデートするため、`web`起動前に4つのSQLite DB（primary / cache / queue / cable）すべてへ `db:prepare` を流すステップを起動処理に挟む（Campfireの`bin/boot`には無い、Beams固有の追加）。

---

## 3. 技術スタック

| 領域 | 採用技術 | 備考 |
|------|----------|------|
| フレームワーク | Rails 8.1 / Ruby 4.0 | アプリモジュール名 `Beams` |
| フロント | Hotwire（Turbo / Stimulus） | **Nodeを使わない** |
| アセット | importmap | Nodeビルド不要。vendored/pinned JSをそのまま読む |
| DB | SQLite（4分割） | `/storage` 配下、ONCEがバックアップ |
| ジョブ | SolidQueue | クエリ非同期実行 |
| キャッシュ | SolidCache | スキーマ・結果キャッシュ |
| WebSocket | SolidCable | Turbo Streamsで結果をプッシュ |
| Webサーバ | Puma + Thruster | port 80 / X-Sendfile（TLS 終端は ONCE 担当） |
| チャート | Chart.js | importmapでピン留め |
| SQLエディタ | CodeMirror 6 | importmapでピン留め。ハイライト・行番号 |
| 認証 | Rails 8標準（has_secure_password） | 自前認証 |
| デプロイ | ONCE（単一Dockerコンテナ） | 単一アプライアンス |

### 3.1 SQLite 4分割（Solid Stack）

| DB | 用途 |
|----|------|
| `storage/production.sqlite3` | メインデータ（クエリ・ダッシュボード・ユーザー・結果キャッシュ等） |
| `storage/production_cache.sqlite3` | SolidCache |
| `storage/production_queue.sqlite3` | SolidQueue |
| `storage/production_cable.sqlite3` | SolidCable |

---

## 4. 初期スコープ（MVP）

### 4.1 認証・ユーザー（→ 決定: 自前認証 / 2ロール）

- メール＋パスワードの自前認証（Rails 8標準）。
- ロールは **admin**（接続・ユーザー管理）/ **member**（クエリ作成・実行・共有）の2段階。
- SSO/Google OAuthは将来オプション。

### 4.2 BigQuery接続（→ 決定: 初期は単一SA、データモデルは複数前提）

- 管理者がサービスアカウント（SA）のJSON鍵 ＋ プロジェクトIDを登録。
- 全クエリは共有SA権限で実行される（＝アプリ側で誰が何を見るかは制御しない。初期は組織フルオープン）。
- SA鍵は `/storage` の SQLite に **平文**で保存する（トピック27 で Active Record Encryption を撤廃）。保護はホスト側のディスク暗号化・ファイルパーミッション・`/storage` ボリュームのアクセス制御に委ねる（詳細: [docs/adr/0002-drop-active-record-encryption.md](adr/0002-drop-active-record-encryption.md) / [docs/INSTALL.md §3](INSTALL.md)）。
- **データモデルは `Connection` を複数持てる形**にしておき、UI・初期運用は1接続のみ。将来、複数接続の使い分けに拡張（→ §7）。

### 4.3 クエリエディタ（→ 決定: CodeMirror + スキーマブラウザ）

- **CodeMirror 6**（importmap）でSQLハイライト・行番号。
- **スキーマブラウザ**: 左ペインにデータセット → テーブル → カラムのツリー。クリックで名前を挿入。
- スキーマは BigQueryメタデータAPI（datasets.list / tables.list / `INFORMATION_SCHEMA.COLUMNS`）で取得し **SQLiteにキャッシュ**。更新は **手動更新ボタン＋初回アクセス時に無ければ取得＋TTL長め（24時間）**。
- オートコンプリート（文脈解析）は次フェーズ。

### 4.4 コスト保護（→ 決定: dry-run表示 ＋ 上限ガード）★差別化の目玉

- 実行前に自動で **dry-run**（`dry_run: true`、課金ゼロ）→「推定 ◯ GB / 約 ¥◯」をボタン横に表示。
- 管理者が `Connection` 単位で「1クエリ最大スキャン量」を設定 → 全実行ジョブに **`maximum_bytes_billed`** を付与。超過ジョブはBigQuery側でエラー停止（課金されない）。
- 上限超過は実行前にdry-runで弾き、具体的なエラーを表示。

### 4.5 パラメータ化クエリ（→ 決定: 基本パラメータを安全バインド）

- `{{ name }}` 記法。型は **文字列 / 数値 / 日付 / 日付範囲** の4種。
- 実行時にフォーム表示。**値は必ずBigQueryのネイティブなパラメータ（`@param`）としてバインド** — 文字列連結は禁止。Redash最大の事故源だったSQLインジェクションを構造的に排除。
- クエリベースの動的ドロップダウンは次フェーズ。

### 4.6 実行・結果（→ 決定: 非同期実行 / 最新1件の圧縮キャッシュ）

- 実行フロー: 実行ボタン → `QueryExecution` を `running` で作成しSolidQueueに投入 → 即「実行中」画面を返す → ジョブ内でBigQueryにジョブ投入＆完了ポーリング → 結果保存 → **Turbo Streams（SolidCable）で結果を画面にプッシュ**。
- **結果は最新の成功1件のみ保存**（古いものは上書き、履歴なし）。
- **二重上限**: 「10,000行 かつ 圧縮後10MB」を超えたら表示用に先頭N行のみ保存し「全件はCSVダウンロード」へ誘導。
- 保存形式: 列スキーマ＋行データを **圧縮blob（MessagePack/JSON + gzip）で1レコード**に格納。結果用テーブルを行数分膨らませない。
- 「SQLiteは結果の小さなキャッシュ置き場であり、データウェアハウスではない」という割り切り。

### 4.7 可視化（→ 決定: Chart.js）

- **Chart.js**（importmap） + Stimulusで描画。折れ線・棒・円・面・散布図。
- テーブル ⇄ チャート切り替え、X軸/Y軸/系列の指定UI。
- CSVエクスポート（X-Sendfileで配信）。

### 4.8 ダッシュボード（→ 決定: 初期からB＝縦積み/簡易段組）

- ウィジェット（クエリの可視化）を **縦積み or 1〜2カラムグリッド** に並べる。
- 並べ替えは順序カラム ＋「上へ/下へ」。**ドラッグ＆ドロップは無し**（自由グリッドは将来）。
- Turbo Frames + 順序カラムで実装。

### 4.9 共有・権限（→ 決定: 組織フルオープン）

- ログインユーザーは全クエリ・全ダッシュボードを閲覧・編集可（社内信頼ベース）。
- 所有者は記録するが、閲覧・編集の制限はしない。
- 細かい権限モデルは作らない（初速優先）。

### 4.10 初回セットアップ（→ 決定: 段階的ウィザード）

初回起動を検知し、専用ウィザードで誘導:

1. 最初のadminアカウント作成（メール＋パスワード）
2. BigQuery接続登録（SA鍵JSONアップロード ＋ プロジェクトID）
3. **接続テスト** — 実際に dry-run と datasets.list を叩いて「✅ 接続成功 / ❌ この権限が足りません（例: `bigquery.jobs.create`）」まで具体診断
4. （任意）コスト上限の初期設定

### 4.11 探しやすさ（→ 決定: 最小）

- クエリ/ダッシュボードを更新日順で一覧＋**タイトル部分一致検索のみ**。
- タグ・お気に入り・SQL全文検索は将来（→ §7）。

---

## 5. 非スコープ（初期に作らないと明示的に決めたもの）

| 項目 | 理由 / 将来扱い |
|------|----------------|
| アラート | 初期不要（明示的に除外） |
| スケジュール実行 | 初期不要 → 将来検討 |
| マルチテナント（SaaS） | 単一組織セルフホストに割り切り。SQLite採用と整合 |
| 個人Google OAuthでのクエリ実行 | ONCEのシンプル思想と相性が悪い。共有SAで割り切り |
| Redashからの移行 | 新規導入向けに集中 → 将来「SQLインポート」検討 |
| グループ/ロール権限 | Redash複雑化の元凶。組織フルオープンで割り切り |
| ダッシュボードの自由グリッド（D&D） | Nodeなしで実装が重い → 将来 |
| 文脈オートコンプリート | スキーマブラウザで代替 → 将来 |
| タグ / お気に入り / 全文検索 | 初期はタイトル検索のみ → 将来 |
| クエリ実行履歴（複数世代） | 最新1件のみ。SQLite肥大化を回避 |
| 公開リンク（ログイン不要） | 将来オプション |

---

## 6. アーキテクチャ詳細

### 6.1 非同期実行とリアルタイム反映

```
[ユーザー]
   │ 実行
   ▼
[Web/Puma] ── QueryExecution(running)作成 ── SolidQueueに投入
   │ 即「実行中」を返す                              │
   ▼                                                ▼
[ブラウザ] ◄── Turbo Stream(SolidCable) ──── [Worker/SolidQueue]
   結果差し込み                                      │ BigQueryジョブ投入→完了ポーリング
                                                     │ 結果を圧縮blobで保存→succeeded
```

### 6.2 同時実行とスレッド（→ 決定: 上限10件程度で割り切り）

- 同時実行は **最大10件程度を上限**とし、超過はキューで待機（UIに「実行待ち」表示）。
- BigQuery待ちジョブはCPUを食わず待つだけなので、**worker側のスレッドはアプリ上限と揃えて確保**する。worker別プロセス（§2.2）により、Pumaのリクエストスレッドと独立にサイズ可能。具体値は `Queries::ExecutionsController::CONCURRENCY_LIMIT` と `config/queue.yml` の `query_execution` ワーカー threads で揃え、queue DB の connection pool（`config/database.yml` の `production:queue.max_connections`）も同期する。
- 将来、規模が増えたら「投げてjob_id保存→一旦離脱→定期的に状態確認」の分割実行に発展させる余地を残す。

### 6.3 結果キャッシュ戦略

- 1クエリ = 最新成功結果1件。圧縮blobで1レコード。二重上限（行数＋バイト数）。
- SQLite肥大化＝ONCEバックアップ肥大化を防ぐための中核設計。

### 6.4 スキーマキャッシュ戦略

- BigQueryメタデータをSQLiteにキャッシュ。手動更新ボタン＋初回取得＋TTL 24時間。
- 毎回叩くと遅く、メタデータ取得にも軽い考慮が要るため。

### 6.5 起動時マイグレーション

- ONCE自動アップデート対応。`web`起動前に4DBへ `db:prepare`。無停止で常に通ること。

---

## 7. 将来ロードマップ

- **複数BigQuery接続**（部署ごとに権限の違うSAを使い分け）
- **スケジュール実行**（SolidQueueの定期実行）
- **Redash SQLインポート**（クエリ本文＋タイトルの最小移行、パラメータ記法変換）
- **ダッシュボード自由グリッド**（D&D、SortableJS等をimportmapで）
- **文脈オートコンプリート**（CodeMirror補完＋スキーマキャッシュ）
- **タグ / お気に入り / SQL全文検索**（SQLiteのFTS5）
- **公開リンク**（トークン付きURL、ログイン不要閲覧）
- **SSO / Google OAuthログイン**（オプション）
- **クエリベースの動的ドロップダウン**

---

## 8. リスクと割り切り

| リスク | 対策 / 割り切り |
|--------|----------------|
| SQLite同時書き込み制約 | 同時実行20件上限。結果はキャッシュのみで肥大化を抑制。マルチテナント非対応 |
| BigQuery待ちジョブのスレッド占有 | worker別プロセス＋スレッド多め。将来は分割実行へ |
| BigQueryメタデータ取得のコスト/遅延 | SQLiteキャッシュ＋TTL＋手動更新 |
| 共有SA権限＝アプリ側で行レベル制御不可 | 初期は組織フルオープンで割り切り（信頼ベース） |
| 巨大結果でのメモリ/容量 | 二重上限＋CSVダウンロード誘導。SQLiteはDWHにしない |
| ONCE自動アップデート時のマイグレーション失敗 | 起動時 `db:prepare` を無停止で通す設計・テスト |
| Nodeなしでの可視化の限界 | Chart.jsで基本チャートに集中。Plotly級のリッチさは狙わない |

---

## 9. 決定ログ（このドキュメントの根拠）

1. 中心軸 = SQLファースト軽量版（B）＋ダッシュボード共有
2. アラート・スケジュール実行 = 初期スコープ外
3. テナント = 単一組織セルフホスト（A）
4. 配布 = ONCE（買い切り単一アプライアンス）
5. BigQuery認証 = 初期は単一SA（A）、データモデルは複数前提
6. アプリ認証 = 自前メール＋パスワード（A）、admin/member
7. 結果保存 = 最新1件の圧縮キャッシュ＋二重上限（B）
8. 実行 = SolidQueue非同期＋Turbo Streams、同時20件上限
9. 可視化 = Chart.js（importmap）（B）
10. プロセス管理 = Campfireに倣う（Thruster＋自前bin/boot＋Procfile）、redis/resqueはSolid Stackに置換、workerは別プロセス
11. 共有・権限 = 組織フルオープン（A）
12. コスト保護 = dry-run表示＋`maximum_bytes_billed`上限ガード（C）★差別化
13. クエリエディタ = CodeMirror＋スキーマブラウザ（B）、補完は将来
14. パラメータ = 基本4型を安全バインド（B）
15. ダッシュボード = 初期から縦積み/簡易段組（B）、自由グリッドは将来
16. 初回セットアップ = 段階的ウィザード＋接続テスト具体診断（A）
17. 移行 = 初期なし（A）、将来SQLインポート
18. 探しやすさ = タイトル検索のみ（A）、タグ/FTS5は将来
19. プロダクト名 = **Beams**
