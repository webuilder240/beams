import { Controller } from "@hotwired/stimulus"
import Sortable from "sortablejs"

// D&D 並び替えコントローラ（トピック19）。
// SortableJS をグリッド要素に適用し、ドロップ確定時（onEnd）に
// DOM 順から data-widget-id を集めて reorder エンドポイントへ PATCH 送信する。
export default class extends Controller {
  static values = { url: String }

  connect() {
    this.sortable = Sortable.create(this.element, {
      animation: 150,
      handle: ".drag-handle",
      ghostClass: "sortable-ghost",
      chosenClass: "sortable-chosen",
      onEnd: this.onEnd.bind(this)
    })
  }

  disconnect() {
    if (this.sortable) {
      this.sortable.destroy()
    }
  }

  onEnd() {
    const widgetIds = Array.from(this.element.children)
      .map(el => el.dataset.widgetId)
      .filter(id => id !== undefined)

    const csrfToken = document.querySelector("meta[name='csrf-token']")?.content

    const body = new URLSearchParams()
    widgetIds.forEach(id => body.append("widget_ids[]", id))

    fetch(this.urlValue, {
      method: "PATCH",
      headers: {
        "X-CSRF-Token": csrfToken,
        "Accept": "text/vnd.turbo-stream.html",
        "Content-Type": "application/x-www-form-urlencoded"
      },
      body: body.toString()
    })
      .then(response => {
        if (response.ok) {
          return response.text()
        }
      })
      .then(html => {
        if (html) {
          Turbo.renderStreamMessage(html)
        }
      })
  }
}
