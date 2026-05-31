import { Controller } from "@hotwired/stimulus"

// スキーマブラウザのツリー操作を担う。
// - データセット/テーブルの折りたたみ展開トグル
// - 名前クリックでカスタムイベント `schema-browser:insert`（detail に名前）を dispatch
//   実際のエディタ側リスナはトピック07（クエリエディタ）で配線する。
//   併せて可能ならクリップボードにコピーする。
export default class extends Controller {
  static targets = ["tables", "columns"]

  connect() {
    // 初期状態は折りたたみ（第1階層のデータセットのみ表示）。
    this.tablesTargets.forEach((el) => (el.hidden = true))
    this.columnsTargets.forEach((el) => (el.hidden = true))
  }

  toggleDataset(event) {
    const dataset = event.currentTarget.closest("[data-schema-browser-target='dataset']")
    const tables = dataset && dataset.querySelector("[data-schema-browser-target='tables']")
    if (tables) tables.hidden = !tables.hidden
  }

  toggleTable(event) {
    const table = event.currentTarget.closest("[data-schema-browser-target='table']")
    const columns = table && table.querySelector("[data-schema-browser-target='columns']")
    if (columns) columns.hidden = !columns.hidden
  }

  insert(event) {
    const name = event.currentTarget.dataset.name
    if (!name) return

    // 疎結合のため、エディタへの挿入はカスタムイベントで通知する（リスナは07で配線）。
    this.dispatch("insert", { detail: { name } })

    if (navigator.clipboard && navigator.clipboard.writeText) {
      navigator.clipboard.writeText(name).catch(() => {})
    }
  }
}
