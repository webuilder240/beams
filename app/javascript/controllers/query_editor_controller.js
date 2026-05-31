import { Controller } from "@hotwired/stimulus"
import { EditorState } from "@codemirror/state"
import { EditorView, keymap, lineNumbers, highlightActiveLine } from "@codemirror/view"
import { defaultKeymap, history, historyKeymap } from "@codemirror/commands"
import { sql } from "@codemirror/lang-sql"
import { syntaxHighlighting, defaultHighlightStyle } from "@codemirror/language"

// クエリエディタ（CodeMirror 6）を <textarea> にかぶせてマウントする。
// - connect(): 隠し textarea（target: input）の値を初期値に EditorView を生成し、
//   SQL ハイライト・行番号・基本キーマップを設定。textarea は非表示にする。
// - エディタ変更時に textarea へリアルタイム同期（dispatchTransaction）。
// - disconnect(): EditorView を destroy() して後始末。
//
// 06（スキーマブラウザ）連携:
//   スキーマブラウザが dispatch するカスタムイベント `schema-browser:insert`
//   （`event.detail.name` に挿入する名前）を document で listen し、
//   現在のカーソル位置にその名前を挿入する。
//   イベント名・detail 構造は 06 の schema_browser_controller.js と一致させること。
export default class extends Controller {
  static targets = ["input", "mount"]

  connect() {
    const initialDoc = this.hasInputTarget ? this.inputTarget.value : ""

    this.view = new EditorView({
      state: EditorState.create({
        doc: initialDoc,
        extensions: [
          lineNumbers(),
          history(),
          highlightActiveLine(),
          syntaxHighlighting(defaultHighlightStyle, { fallback: true }),
          sql(),
          keymap.of([...defaultKeymap, ...historyKeymap])
        ]
      }),
      parent: this.mountTarget,
      dispatchTransactions: (trs) => {
        this.view.update(trs)
        if (trs.some((tr) => tr.docChanged)) this.syncToInput()
      }
    })

    // 非表示にした textarea に値を保持してフォーム送信させる。
    if (this.hasInputTarget) this.inputTarget.style.display = "none"

    // 06 のスキーマブラウザからの名前挿入イベント。
    this.onInsert = this.insertName.bind(this)
    document.addEventListener("schema-browser:insert", this.onInsert)
  }

  disconnect() {
    document.removeEventListener("schema-browser:insert", this.onInsert)
    if (this.view) {
      this.view.destroy()
      this.view = null
    }
  }

  // エディタ内容を隠し textarea に書き戻す。
  // 09（パラメータ化クエリ）連携: SQL 変更を `query-editor:change`
  // （detail.sql に現在の SQL）として dispatch し、parameter-form が
  // `{{ name }}` の増減に応じてフォームフィールドを再描画できるようにする。
  syncToInput() {
    if (!this.hasInputTarget) return

    const sql = this.view.state.doc.toString()
    this.inputTarget.value = sql
    this.dispatch("change", { detail: { sql }, prefix: "query-editor", bubbles: true })
  }

  // `schema-browser:insert`（detail.name）でカーソル位置に名前を挿入する。
  insertName(event) {
    const name = event.detail && event.detail.name
    if (!name || !this.view) return

    const pos = this.view.state.selection.main.head
    this.view.dispatch({
      changes: { from: pos, insert: name },
      selection: { anchor: pos + name.length }
    })
    this.view.focus()
    this.syncToInput()
  }
}
