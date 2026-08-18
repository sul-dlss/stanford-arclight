import { Controller } from "@hotwired/stimulus"

// Briefly shows a skeleton placeholder before revealing its real content,
// to simulate the perceived latency of a real AI response.
export default class extends Controller {
  static targets = ["skeleton", "content"]
  static values = { delay: { type: Number, default: 2000 } }

  connect() {
    this.timeout = setTimeout(() => this.reveal(), this.delayValue)
  }

  disconnect() {
    clearTimeout(this.timeout)
  }

  reveal() {
    this.skeletonTarget.classList.add("d-none")
    this.contentTarget.classList.remove("d-none")
  }
}
