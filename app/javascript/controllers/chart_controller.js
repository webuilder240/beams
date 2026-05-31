import { Controller } from "@hotwired/stimulus"
import Chart from "chart.js/auto"

// 可視化（トピック11）の Chart.js 描画コントローラ。
// `data-chart-config-value`(JSON) を読み <canvas> に折れ線・棒・円・面・散布図を描画する。
// area はサーバ側で type:"line" + fill:true に変換済み。
// counter は Chart.js を使わず単一値をテキスト表示するため、ここでは描画しない。
//
// values:
//   - config: Chart.js の { type, data }（JSON）
//   - type:   chart_type（counter のときは描画スキップ）
// targets:
//   - canvas:  描画先 <canvas>
//   - counter: counter 表示の単一値要素（描画不要・存在確認用）
export default class extends Controller {
  static targets = ["canvas", "counter"]
  static values = { config: Object, type: String }

  connect() {
    if (this.typeValue === "counter") return
    if (!this.hasCanvasTarget) return
    if (!this.hasConfigValue || !this.configValue.type) return

    this.chart = new Chart(this.canvasTarget, {
      type: this.configValue.type,
      data: this.configValue.data,
      options: { responsive: true, maintainAspectRatio: true }
    })
  }

  // values 変更（設定の差し替え）で再描画する。
  configValueChanged() {
    if (!this.chart) return
    this.redraw()
  }

  redraw() {
    this.disconnect()
    this.connect()
  }

  disconnect() {
    if (this.chart) {
      this.chart.destroy()
      this.chart = null
    }
  }
}
