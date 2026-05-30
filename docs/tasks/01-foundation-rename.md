# トピック01: プロジェクト基盤・Beamsリネーム

> アプリモジュール名を `SampleSnsService` から `Beams` へリネームし、認証基盤・暗号化・フロントエンドライブラリ（Tailwind CSS / importmap）・テスト土台を整備する。計画書 §3 / §3.1 に対応。

- **ステータス**: 完了
- **依存**: なし
- **関連計画書**: §3, §3.1, §4.1, §4.2

## ゴール（完了の定義）

- `Beams` モジュール名でアプリが正常起動する（`rails s` でエラーなし）
- `bcrypt` が有効化され `has_secure_password` が使用可能な状態になっている
- Active Record Encryption の primary/deterministic/key_derivation_salt 3キーが `credentials.yml.enc` に保存されている
- `config/importmap.rb` に CodeMirror 6 および Chart.js のピン留めエントリが追加されている（ファイル配置は次トピック以降でよい）
- **Tailwind CSS（`tailwindcss-rails`、Node非依存のスタンドアロンCLI）が導入され、レイアウトに適用されている**。`bin/rails tailwindcss:build` でCSSがビルドでき、本番 `assets:precompile` 時に自動ビルドされる
- SQLite 4分割構成（`database.yml`）が本番環境で正しく設定されていることを確認済み
- `app/views/layouts/application.html.erb` に Tailwind でスタイルされたナビゲーション骨格が存在する
- `bundle exec rspec` が通り、SimpleCov カバレッジ **85% 以上**（本タスク群の制約。`spec/spec_helper.rb` の閾値を 85% に設定。→ [[00-overview]] のコーディング規約参照）
- `bin/rubocop` がエラーなし
- `bin/brakeman --no-pager` がエラーなし

## 前提・参照

- `config/application.rb:9` — 現在の `module SampleSnsService`
- `Gemfile` — `gem "bcrypt"` がコメントアウト済み（`# gem "bcrypt", "~> 3.1.7"`）
- `config/database.yml` — production の 4分割設定は既に定義済み。development/test は単一 SQLite
- `config/importmap.rb` — 現在 Hotwire のみピン留め
- `Gemfile` — アセットパイプラインは `propshaft`。Tailwind は `tailwindcss-rails`（スタンドアロン CLI バイナリ）を使い **Node を導入しない**（計画書「Node を使わない」と整合）
- `spec/spec_helper.rb` — SimpleCov 閾値が現状 90%。本タスクで **85%** に変更する（`CLAUDE.md` のコーディング制約条件に合わせる）
- `spec/support/factory_bot.rb` — FactoryBot DSL 自動読み込み済み
- `app/views/layouts/application.html.erb` — 現在は標準 scaffold レイアウト

## タスク

### モジュールリネーム

- [x] `config/application.rb` の `module SampleSnsService` を `module Beams` に変更する (`config/application.rb`)
  - 受け入れ条件: `bin/rails runner "puts Rails.application.class.module_parent_name"` が `Beams` を返す
- [x] `config/application.rb` 内および全 `config/` 配下で `SampleSnsService` を参照している箇所を `Beams` に一括置換する (`config/` 配下全ファイル)
  - 受け入れ条件: `grep -r "SampleSnsService" config/` が何も出力しない
- [x] `config/environments/` 配下および `config/initializers/` 配下に `SampleSnsService` 参照があれば `Beams` に置換する (`config/environments/`, `config/initializers/`)
  - 受け入れ条件: `grep -r "SampleSnsService" config/` が何も出力しない（上タスクと合わせて確認）
- [x] `app/` 配下（controllers, mailers, jobs 等の名前空間）に `SampleSnsService` 参照があれば `Beams` に置換する (`app/`)
  - 受け入れ条件: `grep -r "SampleSnsService" app/` が何も出力しない
- [x] `spec/` 配下に `SampleSnsService` 参照があれば `Beams` に置換する (`spec/`)
  - 受け入れ条件: `grep -r "SampleSnsService" spec/` が何も出力しない
- [x] `Dockerfile` 内のコメント・変数に `sample_sns_service` があれば `beams` に修正する (`Dockerfile`)
  - 受け入れ条件: Dockerfile に旧名称が残っていない

### bcrypt 有効化

- [x] `Gemfile` の `# gem "bcrypt", "~> 3.1.7"` のコメントアウトを外す (`Gemfile`)
  - 受け入れ条件: `bundle install` が成功する
- [x] `bundle install` を実行して `Gemfile.lock` を更新する (`Gemfile.lock`)
  - 受け入れ条件: `bundle list | grep bcrypt` が bcrypt を表示する

### Active Record Encryption 設定

- [x] `bin/rails db:encryption:init` を実行し、出力された 3キー（`primary_key`, `deterministic_key`, `key_derivation_salt`）を `bin/rails credentials:edit` で `active_record_encryption:` 以下に保存する (`config/credentials.yml.enc`)
  - 受け入れ条件: `bin/rails runner "ActiveRecord::Encryption.config.primary_key"` がキー文字列を返す（エラーにならない）
- [x] `config/application.rb` または `config/initializers/` に Active Record Encryption を有効化する設定を追加する（`config.active_record.encryption.primary_key` 等、Rails 8 の推奨方式に従う）(`config/application.rb` または `config/initializers/encryption.rb`)
  - 受け入れ条件: `bin/rails runner "ActiveRecord::Encryption.config.primary_key"` が credentials から読んだ値を返す

### importmap ピン留め準備

- [x] `bin/importmap pin @codemirror/state @codemirror/view @codemirror/lang-sql` 等を実行し、CodeMirror 6 コアパッケージを CDN pin で `config/importmap.rb` に追加する (`config/importmap.rb`)
  - 受け入れ条件: `config/importmap.rb` に該当 `@codemirror/*` の pin エントリが追加され、`bin/importmap audit` がエラーなしで通る
  - 注記: vendoring（`vendor/javascript/` への配置）は行わない。将来オフライン要件が出たら vendoring へ移行すること
- [x] `bin/importmap pin chart.js` を実行し、Chart.js を CDN pin で `config/importmap.rb` に追加する (`config/importmap.rb`)
  - 受け入れ条件: `config/importmap.rb` に `chart.js` の pin エントリが追加され、`bin/importmap audit` がエラーなしで通る
  - 注記: vendoring は行わない。将来オフライン要件が出たら vendoring へ移行すること

### Tailwind CSS 導入

- [x] `Gemfile` に `gem "tailwindcss-rails"` を追加し `bundle install` する (`Gemfile`, `Gemfile.lock`)
  - 受け入れ条件: `bundle list | grep tailwindcss-rails` が表示される。Node 非依存のスタンドアロン CLI バイナリを使う（npm/yarn 不要）
- [x] `bin/rails tailwindcss:install` を実行し、初期構成を生成する（`app/assets/tailwind/application.css`、`app/assets/builds/`、レイアウトへの `stylesheet_link_tag "tailwind"` 追加） (`app/assets/tailwind/application.css`, `app/views/layouts/application.html.erb`)
  - 受け入れ条件: `app/assets/tailwind/application.css` が生成され、`application.html.erb` に Tailwind のスタイルリンクが入る
- [x] `bin/rails tailwindcss:build` で CSS をビルドできることを確認する (`app/assets/builds/tailwind.css`)
  - 受け入れ条件: `app/assets/builds/tailwind.css` が生成され、`bin/rails s` で Tailwind クラス（例 `text-3xl font-bold`）が効く
- [x] 開発時の CSS ウォッチを `bin/dev`（`Procfile.dev`）に `tailwindcss:watch` として組み込む。本番は `assets:precompile` 時に自動ビルドされることを確認する (`Procfile.dev`)
  - 受け入れ条件: `bin/dev` 起動で CSS 変更が反映される。`RAILS_ENV=production bin/rails assets:precompile` で `tailwind.css` が生成される
  - 注記: 本番の単一コンテナ起動（[[02-once-deployment]] の Dockerfile / `bin/boot`）でも `assets:precompile` がビルドを含むことを確認する
- [x] 最小のデザイン規約（色・タイポグラフィ・ボタン/フォーム/テーブルの共通ユーティリティ）を `app/assets/tailwind/application.css` に `@layer` 等でメモ的に定義する（過剰設計しない）
  - 受け入れ条件: 後続のビュー系トピック（[[07-query-editor]] [[11-visualization]] [[12-dashboard]] 等）が参照できる最小のデザイン規約が記述されている

### SQLite 4分割確認

- [x] `config/database.yml` の production 4分割定義（primary / cache / queue / cable）と `storage/` パスが計画書 §3.1 と一致していることを確認する (`config/database.yml`)
  - 受け入れ条件: `database.yml` の production キーに 4DB が定義されており、パスが `storage/production*.sqlite3` 形式になっている（現状確認のみ、変更不要なら確認で完了）
- [x] `config/cache.yml`, `config/queue.yml`, `config/cable.yml` が Solid Stack の各 DB を向いていることを確認する (`config/cache.yml`, `config/queue.yml`, `config/cable.yml`)
  - 受け入れ条件: 各 yml が適切な database キーを参照している

### ベースレイアウト・ナビゲーション

- [x] `app/views/layouts/application.html.erb` の `<title>` を `Beams` に変更する (`app/views/layouts/application.html.erb`)
  - 受け入れ条件: ブラウザタブに「Beams」と表示される
- [x] `app/views/layouts/application.html.erb` にナビゲーションバー骨格を **Tailwind クラスで** 追加する（アプリ名ロゴ部分、ログイン/ログアウトリンクのプレースホルダ） (`app/views/layouts/application.html.erb`)
  - 受け入れ条件: `/up` にアクセスした際に Tailwind が適用されたナビが崩れず表示される（ナビ内リンクのリンク先は後続トピックで実装）

### テスト・Lint 土台整備

- [x] `spec/spec_helper.rb` の SimpleCov 最低カバレッジ閾値を **85%** に設定する（`minimum_coverage 85`） (`spec/spec_helper.rb`)
  - 受け入れ条件: 閾値が 85% になっている（`CLAUDE.md` のコーディング制約条件と一致）
- [x] `bundle exec rspec` を実行し、既存 spec がすべて通ることを確認する (`spec/`)
  - 受け入れ条件: exit code 0、SimpleCov カバレッジが **85% 以上**（既存 spec が空に近い場合は SimpleCov の `add_filter` で計測対象外を整理する）
- [x] `bin/rubocop` を実行し、違反があれば `bin/rubocop -a` で自動修正する (`全 Ruby ファイル`)
  - 受け入れ条件: `bin/rubocop` が exit code 0
- [x] `bin/brakeman --no-pager` を実行し、警告がないことを確認する
  - 受け入れ条件: Brakeman が警告 0 件で終了する
- [x] `bin/bundler-audit` を実行し、既知の脆弱性がないことを確認する
  - 受け入れ条件: bundler-audit が exit code 0

## 動作確認

- [x] `bin/rails s` でサーバーが起動し、`http://localhost:3000/up` が 200 を返す
- [x] `bin/rails runner "puts Rails.application.class.module_parent_name"` が `Beams` を出力する
- [x] `bin/rails runner "ActiveRecord::Encryption.config.primary_key"` がエラーなしで実行される
- [x] `bundle exec rspec` が全 spec パスかつ SimpleCov **85% 以上**で終了する
- [x] `bin/rubocop` が exit code 0

## 未決事項・質問

- ✅決定: CodeMirror 6 および Chart.js の importmap ピン留めは CDN pin で統一（2026-05-31）。将来オフライン運用が要件化したら vendoring へ移行余地あり。
- ✅決定: SimpleCov の最低カバレッジ閾値は **85%**（本タスク群の制約）。`CLAUDE.md` の 90% 記述とは差異があるため、`CLAUDE.md` 側の追従も別途検討する。
- Active Record Encryption の設定方式（credentials vs 環境変数）は ONCE のデプロイ方式（`RAILS_MASTER_KEY` 環境変数渡し）と整合する形を確認すること。
