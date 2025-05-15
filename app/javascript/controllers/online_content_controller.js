import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = [ 'link' ]

  connect() {
    // If the oembed-loaded event fires we know the oembed endpoint is valid
    // so we can hide the fallback purl link
    window.addEventListener('oembed-loaded', (event) => {
      this.removeEmbededLink(event)
    }, { once: true })
  }

  // Either hide the whole container if the fallback link is the only one in the list
  // or remove the link from the list, leaving the container visible with the other links
  removeEmbededLink(event) {
    const embedUrl = event.detail.embedUrl
    if (this.isOnlyOnlineContentLink(embedUrl)) {
      this.element.classList.add('d-none')
    } else {
      this.removeEmbeddedLinkFromList(embedUrl)
    }
  }

  // Checks whether the fallback link is the only one in the list
  isOnlyOnlineContentLink(embedUrl) {
    return this.onlineContentLinks().length === 1 &&
      this.onlineContentLinks().includes(embedUrl)
  }

  // Returns an array of the online content link href values
  onlineContentLinks() {
    return this.linkTargets.map(function(link) {
      return link.dataset.hrefValue
    })
  }

  // Hides the fallback link leaving the other links visible
  removeEmbeddedLinkFromList(embedUrl) {
    this.linkTargets.forEach((link) => {
      if (link.dataset.hrefValue === embedUrl) {
        link.classList.add('d-none')
      }
    })
  }
}
