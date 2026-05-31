import { Controller } from "@hotwired/stimulus"

// 実行時パラメータ入力フォームを、SQL 内の `{{ name }}` / `{{ name:type }}` に
// 合わせて動的に増減させる。
//
// 07（クエリエディタ）連携:
//   query-editor コントローラが SQL 変更時に dispatch する `query-editor:change`
//   （event.detail.sql に現在の SQL）を document で listen し、パラメータを
//   再パースしてフィールドを描画し直す。サーバ（Query#parameters）と同じ
//   フォールバック規則（不明型→string、同名は最初の出現に正規化）を踏襲する。
//
// 値は params[:query_params][name]（date_range は [start]/[end]）で送られる。
// 全パラメータ必須運用のため、各フィールドに HTML5 required を付与する。
export default class extends Controller {
  static targets = ["fields"]

  // サーバ（Query::PARAMETER_PATTERN）と同等の記法。
  static PATTERN = /\{\{\s*([a-zA-Z_]\w*)\s*(?::\s*(\w+)\s*)?\}\}/g
  static SUPPORTED_TYPES = ["string", "number", "date", "date_range"]

  connect() {
    this.onSqlChange = this.handleSqlChange.bind(this)
    document.addEventListener("query-editor:change", this.onSqlChange)
  }

  disconnect() {
    document.removeEventListener("query-editor:change", this.onSqlChange)
  }

  handleSqlChange(event) {
    const sql = (event.detail && event.detail.sql) || ""
    this.render(this.parse(sql))
  }

  // `{{ name:type }}` をパースし [{ name, type }] を返す（出現順・同名は正規化）。
  parse(sql) {
    const seen = new Set()
    const params = []
    let match
    this.constructor.PATTERN.lastIndex = 0
    while ((match = this.constructor.PATTERN.exec(sql)) !== null) {
      const name = match[1]
      if (seen.has(name)) continue
      seen.add(name)
      const rawType = match[2]
      const type = this.constructor.SUPPORTED_TYPES.includes(rawType) ? rawType : "string"
      params.push({ name, type })
    }
    return params
  }

  render(params) {
    if (!this.hasFieldsTarget) return

    this.fieldsTarget.innerHTML = ""
    params.forEach((param) => this.fieldsTarget.appendChild(this.buildField(param)))
  }

  buildField({ name, type }) {
    const wrapper = document.createElement("div")
    wrapper.className = "space-y-1"

    const label = document.createElement("label")
    label.className = "block text-sm font-medium"
    label.textContent = name
    wrapper.appendChild(label)

    if (type === "date_range") {
      wrapper.appendChild(this.dateRangeFields(name))
    } else {
      wrapper.appendChild(this.scalarField(name, type))
    }
    return wrapper
  }

  scalarField(name, type) {
    const input = document.createElement("input")
    input.type = type === "number" ? "number" : type === "date" ? "date" : "text"
    if (type === "number") input.step = "any"
    input.name = `query_params[${name}]`
    input.required = true
    input.className = "w-full rounded border border-gray-300 px-3 py-2"
    return input
  }

  dateRangeFields(name) {
    const row = document.createElement("div")
    row.className = "flex items-center gap-2"
    ;["start", "end"].forEach((bound, index) => {
      if (index === 1) {
        const sep = document.createElement("span")
        sep.className = "text-gray-500"
        sep.textContent = "〜"
        row.appendChild(sep)
      }
      const input = document.createElement("input")
      input.type = "date"
      input.name = `query_params[${name}][${bound}]`
      input.required = true
      input.className = "rounded border border-gray-300 px-3 py-2"
      row.appendChild(input)
    })
    return row
  }
}
