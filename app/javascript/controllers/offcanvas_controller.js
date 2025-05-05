import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["header"]

  connect() {
    this.panel = document.querySelector('.collection-sidebar #sidebar')
    if (!this.panel) {
      console.warn("Offcanvas panel not found in DOM")
      return
    }

    this.handleResize = this.updatePanelPosition.bind(this)
    window.addEventListener('resize', this.handleResize)

    this.updatePanelPosition()
  }

  disconnect() {
    window.removeEventListener('resize', this.handleResize)
  }

  updatePanelPosition() {
    // Only run this behavior on small screens
    if (window.innerWidth < 992) {
      this.positionPanelBelowHeader()
    } else {
      this.resetPanelStyles()
    }
  }

  positionPanelBelowHeader() {
    const headerBottom = this.headerTarget.getBoundingClientRect().bottom
    this.panel.style.top = `${headerBottom}px`
    this.panel.style.position = 'fixed'
    this.panel.style.height = `calc(100vh - ${headerBottom}px)`
  }

  resetPanelStyles() {
    this.panel.style.top = ''
    this.panel.style.position = ''
    this.panel.style.height = ''
  }
}
