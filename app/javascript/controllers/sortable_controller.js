import { Controller } from "@hotwired/stimulus"
import Sortable from "sortablejs"

// D&D 並び替えコントローラ（トピック19）。
// SortableJS をグリッド要素に適用し、ドロップ確定時（onEnd）に
// DOM 順から data-widget-id を集めて widget_order エンドポイントへ PATCH 送信する。
// 失敗時（4xx/5xx・ネットワークエラー）は DOM をドラッグ前の順序へ復元し、
// toast:show（type: error）カスタムイベントで画面にエラー通知する。
export default class extends Controller {
  static values = { url: String }

  connect() {
    this.sortable = Sortable.create(this.element, {
      animation: 150,
      handle: ".drag-handle",
      ghostClass: "sortable-ghost",
      chosenClass: "sortable-chosen",
      // HTML5 ネイティブ drag ではなくポインタ/マウスイベント駆動にする。
      // 合成マウスイベント（テストの Playwright 操作）でも安定して発火させるため。
      forceFallback: true,
      onEnd: this.onEnd.bind(this)
    })

    // SortableJS の初期化完了マーカー（System Spec の待機判定用。振る舞いには影響しない）。
    this.element.dataset.sortableReady = "true"
  }

  disconnect() {
    if (this.sortable) {
      this.sortable.destroy()
      this.sortable = null
    }
  }

  // onEnd は SortableJS のドロップ確定時に呼ばれる。
  // event は SortableJS の Sortable.Event で、event.oldIndex / event.newIndex に
  // ドラッグ要素の移動前後のインデックスが入る（同じなら順序変化なし）。
  onEnd(event) {
    // 順序が変わっていなければサーバへ送る必要はない（無駄な PATCH を防ぐ）。
    if (event && event.oldIndex === event.newIndex) {
      return
    }

    // 送信前に現在の DOM 順序（ドラッグ後の状態）を widget 要素配列として保持。
    // 失敗時にこれをもとに元の順序（ドラッグ前）へ復元する。
    const currentChildren = Array.from(this.element.children)

    // ドラッグ前の順序を oldIndex / newIndex を使って逆算する。
    // SortableJS はドロップ確定時に onEnd を呼ぶ時点で DOM は既に新しい順序になっている。
    // oldIndex → newIndex へ移動したので、その逆（newIndex から oldIndex へ戻す）で元順序を再現。
    const originalChildren = [ ...currentChildren ]
    if (event && event.oldIndex !== undefined && event.newIndex !== undefined) {
      const moved = originalChildren.splice(event.newIndex, 1)[0]
      originalChildren.splice(event.oldIndex, 0, moved)
    }

    const widgetIds = currentChildren
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
        if (!response.ok) {
          throw new Error(`Reorder request failed: ${response.status}`)
        }
        return response.text()
      })
      .then(html => {
        if (html) {
          Turbo.renderStreamMessage(html)
        }
      })
      .catch(error => {
        // ネットワークエラー / 4xx・5xx 応答。
        // DOM をドラッグ前の順序へ復元してからトースト通知する。
        console.error("[sortable] reorder failed", error)
        this._restoreOrder(originalChildren)
        window.dispatchEvent(new CustomEvent("toast:show", {
          detail: { message: "並び替えの保存に失敗しました", type: "error" }
        }))
      })
  }

  // DOM の子要素を指定の順序（元の順序の配列）に並べ直す。
  _restoreOrder(orderedChildren) {
    orderedChildren.forEach(child => {
      this.element.appendChild(child)
    })
  }
}
