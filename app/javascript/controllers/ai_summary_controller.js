import { Controller } from "@hotwired/stimulus"

// Allows the AI summary panel to be dismissed from view.
export default class extends Controller {
  close() {
    this.element.remove()
  }
}
