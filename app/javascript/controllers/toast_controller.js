import { Controller } from "@hotwired/stimulus"

// 汎用トースト通知コントローラ（トピック19追加対応）。
// レイアウトのコンテナに data-controller="toast" を付与して使う。
// 任意の箇所から以下のようにイベントを発火するとトーストが表示される:
//   window.dispatchEvent(new CustomEvent("toast:show", { detail: { message, type } }))
// type: "error" → 赤系スタイル（bg-red-50 border-red-200 text-red-700）
// type: "notice" → 緑系スタイル
// AUTO_DISMISS_MS ミリ秒後に自動消滅。手動クローズボタンでも閉じられる。
export default class extends Controller {
  static AUTO_DISMISS_MS = 4000

  connect() {
    this._handler = this._onToastShow.bind(this)
    window.addEventListener("toast:show", this._handler)
  }

  disconnect() {
    window.removeEventListener("toast:show", this._handler)
  }

  _onToastShow(event) {
    const { message, type = "notice" } = event.detail || {}
    if (!message) return

    const toast = document.createElement("div")
    toast.setAttribute("role", "alert")
    toast.className = this._classesFor(type)
    toast.innerHTML = `
      <span class="flex-1">${this._escapeHtml(message)}</span>
      <button type="button" class="ml-3 shrink-0 text-current opacity-70 hover:opacity-100" aria-label="閉じる">✕</button>
    `
    toast.querySelector("button").addEventListener("click", () => this._dismiss(toast))
    this.element.appendChild(toast)

    // 自動消滅
    setTimeout(() => this._dismiss(toast), this.constructor.AUTO_DISMISS_MS)
  }

  _dismiss(toast) {
    if (toast.parentNode) {
      toast.parentNode.removeChild(toast)
    }
  }

  _classesFor(type) {
    const base = "flex items-center rounded border px-4 py-3 text-sm shadow-md mb-2"
    if (type === "error") {
      return `${base} bg-red-50 border-red-200 text-red-700`
    }
    // notice / default
    return `${base} bg-green-50 border-green-200 text-green-700`
  }

  _escapeHtml(str) {
    return String(str)
      .replace(/&/g, "&amp;")
      .replace(/</g, "&lt;")
      .replace(/>/g, "&gt;")
      .replace(/"/g, "&quot;")
  }
}
