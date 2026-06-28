# Pin npm packages by running ./bin/importmap

pin "application"
pin "@hotwired/turbo-rails", to: "turbo.min.js"
pin "@hotwired/stimulus", to: "stimulus.min.js"
pin "@hotwired/stimulus-loading", to: "stimulus-loading.js"
pin_all_from "app/javascript/controllers", under: "controllers"

# CodeMirror 6 (CDN pin via esm.sh)
# Use `?external=...` to keep all sub-packages resolving against the same
# @codemirror/state etc. via the importmap (otherwise esm.sh inlines its own
# copies → "multiple instances of @codemirror/state are loaded").
CODEMIRROR_EXTERNAL = "@codemirror/state,@codemirror/view,@codemirror/commands,@codemirror/language,@codemirror/autocomplete,@codemirror/lang-sql,@lezer/common,@lezer/highlight,@lezer/lr,@marijn/find-cluster-break,crelt,style-mod,w3c-keyname".freeze

pin "@codemirror/state", to: "https://esm.sh/@codemirror/state@6.6.0?external=#{CODEMIRROR_EXTERNAL}"
pin "@codemirror/view", to: "https://esm.sh/@codemirror/view@6.43.0?external=#{CODEMIRROR_EXTERNAL}"
pin "@codemirror/commands", to: "https://esm.sh/@codemirror/commands@6.10.3?external=#{CODEMIRROR_EXTERNAL}"
pin "@codemirror/lang-sql", to: "https://esm.sh/@codemirror/lang-sql@6.10.0?external=#{CODEMIRROR_EXTERNAL}"
pin "@codemirror/autocomplete", to: "https://esm.sh/@codemirror/autocomplete@6.20.2?external=#{CODEMIRROR_EXTERNAL}"
pin "@codemirror/language", to: "https://esm.sh/@codemirror/language@6.12.3?external=#{CODEMIRROR_EXTERNAL}"
pin "@lezer/common", to: "https://esm.sh/@lezer/common@1.5.2?external=#{CODEMIRROR_EXTERNAL}"
pin "@lezer/highlight", to: "https://esm.sh/@lezer/highlight@1.2.3?external=#{CODEMIRROR_EXTERNAL}"
pin "@lezer/lr", to: "https://esm.sh/@lezer/lr@1.4.10?external=#{CODEMIRROR_EXTERNAL}"
pin "@marijn/find-cluster-break", to: "https://esm.sh/@marijn/find-cluster-break@1.0.2?external=#{CODEMIRROR_EXTERNAL}"
pin "crelt", to: "https://esm.sh/crelt@1.0.6?external=#{CODEMIRROR_EXTERNAL}"
pin "style-mod", to: "https://esm.sh/style-mod@4.1.3?external=#{CODEMIRROR_EXTERNAL}"
pin "w3c-keyname", to: "https://esm.sh/w3c-keyname@2.2.8?external=#{CODEMIRROR_EXTERNAL}"

# Chart.js (CDN pin via esm.sh)。`chart.js/auto` は全コントローラ自動登録ビルド。
pin "chart.js", to: "https://esm.sh/chart.js@4.4.9"
pin "chart.js/auto", to: "https://esm.sh/chart.js@4.4.9/auto"

# SortableJS（ドラッグ&ドロップ並び替え。トピック19）
pin "sortablejs", to: "https://esm.sh/sortablejs@1.15.6"
