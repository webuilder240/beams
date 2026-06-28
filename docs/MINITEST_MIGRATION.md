# RSpec → Minitest 移行とテスト並列実行

## 背景

- 旧構成: RSpec + FactoryBot + Faker（依存 gem 3 つ）
- 新構成: Minitest（Rails 標準）+ fixtures + TestData ヘルパー（依存 gem ゼロ追加）
- 並列実行: Rails 標準の `parallelize(workers: :number_of_processors)`（gem 追加不要）

## ディレクトリ構成

```
test/
├── test_helper.rb                       # parallelize 設定・TestData include・Object#stub 互換
├── application_system_test_case.rb      # system test 基底（rack_test / Playwright）
├── support/
│   └── test_data.rb                     # create_user/create_query などのファクトリ代替
├── models/                              # ActiveSupport::TestCase
├── jobs/                                # ActiveJob::TestCase
├── helpers/                             # ActionView::TestCase
├── lib/beams/                           # 運用スクリプト用
├── integration/                         # ActionDispatch::IntegrationTest
├── controllers/                         # ActionController::TestCase
└── system/                              # System tests (rack_test / Playwright)
```

## 並列化の仕組み（gem 追加なし）

`test/test_helper.rb`:

```ruby
parallelize(workers: ENV.fetch("PARALLEL_WORKERS", :number_of_processors))
```

- Rails 8.1 標準 `ActiveSupport::TestCase#parallelize`。`fork` ベース。
- SQLite では worker ごとに `storage/test-<worker_id>.sqlite3` が自動で作られる。
- スキーマは `db/schema.rb` から各 worker DB に load される。
- gem 追加（parallel_tests など）は不要。

`PARALLEL_WORKERS=1` を指定すればシリアル実行（ベンチマーク比較や並列で再現しないバグ調査用）。

## パフォーマンス比較（system 以外、全 72 ファイル変換後）

| 構成 | テスト実行時間 | wall clock | runs/examples | failures |
|---|---|---|---|---|
| **RSpec シリアル**（旧） | 9.22 秒 | 10.49 秒 | 483 examples | 0 |
| **Minitest シリアル** | 8.30 秒 | 9.07 秒 | 483 runs | 0 |
| **Minitest 並列 (20 cores)** | 3.18 秒 | 4.03 秒 | 483 runs | 0 |

### 改善率

- **wall clock**: RSpec 10.49 秒 → Minitest 並列 4.03 秒 = **約 2.6 倍高速化** （約 62% 削減）
- **Minitest 単体（シリアル）**: 10.49 秒 → 9.07 秒 = 約 14% 高速化
- **並列効果（Minitest シリアル vs 並列）**: 9.07 秒 → 4.03 秒 = **約 2.25 倍高速化**
- Boot/load 時間が一定のため、テスト数が増えると並列効果はさらに伸びる余地あり

### 並列実行のための CSV 出力パス分離

ジョブが書き出す全件 CSV は `storage/csv/<id>.csv.gz` だが、これは worker 間で共有されるため
並列実行で race condition の原因になる。次の 2 点で worker 隔離する:

- アプリ側: `QueryExecutionJob#write_csv` と `CsvExportsController#show` が `ENV["BEAMS_CSV_PATH"]` を読む（未設定なら従来通り `storage/csv`）。
- テスト側: `test_helper.rb` の `parallelize_setup` で `ENV["BEAMS_CSV_PATH"] = Rails.root.join("tmp/test-csv-#{worker}").to_s` を設定。`parallelize_teardown` で worker dir を掃除。

- Minitest シリアル単体でも RSpec より約 12% 速い（boot time の短縮と Minitest 自体の軽量さ）。
- 並列化により **wall clock で 2.6 倍速** （RSpec 比）。CPU 効率では 8.15s → 3.34s で 2.4 倍。
- Boot time（rails/test_help の load）が支配的なため、テスト数増加に対する並列の効果は線形ではない。

## 既知の並列実行リスク

- `storage/csv/<id>.csv.gz` のようにファイルシステム上の共有パスを使うテストは worker 間で衝突する可能性あり。
- 現状確認している事例: `Queries::Executions::CsvExportsTest` の 2 件（並列実行時のみ）。
- 対策: テスト側で worker ごとに独立 path を使うか、 system test に切り出す。
- シリアル実行（`PARALLEL_WORKERS=1`）では 0 failures。

## TestData ヘルパー

FactoryBot を捨て、`test/support/test_data.rb` のシンプルな module で代替。
`test_helper.rb` で `include TestData` 済みのため、テスト内でそのまま呼べる。

```ruby
create_user(role: "admin")
create_query(bigquery_connection: create_bigquery_connection)
create_succeeded_query_execution(query: q)
```

## Object#stub の互換実装

minitest 6.0 では `Object#stub` が標準で提供されない（minitest 5 では `minitest/mock` 経由で利用できた）。
gem を追加せずに済ませるため `test_helper.rb` で互換実装を入れている:

```ruby
class Object
  def stub(method_name, value_or_proc)
    # define_singleton_method で一時上書き、ensure で remove_method する
    ...
  end
end
```

## 実行方法

```bash
bin/rails test                              # 全テスト（自動的に並列実行）
bin/rails test test/models                  # 単一ディレクトリ
bin/rails test test/models/user_test.rb     # 単一ファイル
bin/rails test test/models/user_test.rb:42  # 特定行

PARALLEL_WORKERS=1 bin/rails test           # シリアル実行
SKIP_COVERAGE_CHECK=1 bin/rails test        # SimpleCov の 85% 閾値チェックを無効化
```

## カバレッジ

- `test/test_helper.rb` に SimpleCov 設定を維持（旧 `spec/spec_helper.rb` から移植）
- 閾値 85% 未満で exit 2、レポートは `coverage/index.html`
- system 単体実行時など部分実行のときは `SKIP_COVERAGE_CHECK=1` で閾値チェックを無効化
