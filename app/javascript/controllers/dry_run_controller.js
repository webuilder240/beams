import { Controller } from "@hotwired/stimulus"

// dry-run（コスト保護★）コントローラ。
// クエリエディタの SQL が変化したら 500ms デバウンスで
// POST /queries/:id/dry_run に現在の SQL 本文を送り、推定スキャン量（GB）と
// 推定コスト（円）を表示する。上限超過時は警告バナーを出し、実行ボタンを非活性にする。
//
// values:
//   - url:        dry-run エンドポイント（POST 先）
// targets:
//   - input:      SQL 本文を保持する隠し textarea（query-editor と共有）
//   - result:     「推定 X.X GB / 約 ¥Y」を表示する要素
//   - warning:    上限超過時の警告バナー（hidden をトグル）
//   - warningText: 警告本文
//   - submit:     実行/保存ボタン（超過時に disabled）
export default class extends Controller {
  static targets = ["input", "result", "warning", "warningText", "submit"]
  static values = { url: String, debounce: { type: Number, default: 500 } }

  connect() {
    this.timer = null
    this.onInput = this.scheduleRun.bind(this)
    if (this.hasInputTarget) {
      this.inputTarget.addEventListener("input", this.onInput)
    }
    // 初期表示で一度推定する（保存済み SQL のコストを即表示）。
    this.scheduleRun()
  }

  disconnect() {
    if (this.timer) clearTimeout(this.timer)
    if (this.hasInputTarget) {
      this.inputTarget.removeEventListener("input", this.onInput)
    }
  }

  scheduleRun() {
    if (this.timer) clearTimeout(this.timer)
    this.timer = setTimeout(() => this.run(), this.debounceValue)
  }

  async run() {
    const sql = this.hasInputTarget ? this.inputTarget.value : ""
    if (!sql.trim()) return

    try {
      const response = await fetch(this.urlValue, {
        method: "POST",
        headers: {
          "Content-Type": "application/json",
          "Accept": "application/json",
          "X-CSRF-Token": this.csrfToken()
        },
        body: JSON.stringify({ sql })
      })
      const data = await response.json()
      this.render(data)
    } catch (e) {
      this.renderError("推定の取得に失敗しました")
    }
  }

  render(data) {
    if (data.error && !data.over_limit) {
      this.renderError(data.error)
      return
    }

    if (this.hasResultTarget) {
      const gb = data.gb == null ? "?" : data.gb
      const yen = data.yen == null ? "?" : data.yen
      this.resultTarget.textContent = `推定 ${gb} GB / 約 ¥${yen}`
    }

    this.toggleLimit(data)
  }

  renderError(message) {
    if (this.hasResultTarget) this.resultTarget.textContent = message
    this.clearLimit()
  }

  toggleLimit(data) {
    if (data.over_limit) {
      if (this.hasWarningTarget) this.warningTarget.hidden = false
      if (this.hasWarningTextTarget) {
        this.warningTextTarget.textContent =
          data.error || `推定 ${data.gb} GB は接続の上限 ${data.limit_gb} GB を超えています`
      }
      this.disableSubmit(true)
    } else {
      this.clearLimit()
    }
  }

  clearLimit() {
    if (this.hasWarningTarget) this.warningTarget.hidden = true
    this.disableSubmit(false)
  }

  disableSubmit(disabled) {
    if (this.hasSubmitTarget) this.submitTarget.disabled = disabled
  }

  csrfToken() {
    const el = document.querySelector("meta[name='csrf-token']")
    return el ? el.content : ""
  }
}
