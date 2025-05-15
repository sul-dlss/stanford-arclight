import OembedController from "arclight/oembed_controller";

// Add support for additional parameters
export default class SulEmbedController extends OembedController {
  static values = {
    hideTitle: Boolean,
    ...super.values,
  };

  // Pass extra parameters to sul-embed
  findOEmbedEndPoint(body) {
    return super.findOEmbedEndPoint(body, this.getExtraParams());
  }

  // For a full list of parameters supported by the viewer, see:
  // https://github.com/sul-dlss/sul-embed/blob/main/lib/embed/request.rb
  getExtraParams() {
    return {
      ...(this.hideTitleValue && { hide_title: this.hideTitleValue })
    };
  }

  // This gets called once we know the oembed endpoint is valid so
  // we disptach an event to let us know we can remove the fallback purl link
  loadEndPoint(oEmbedEndPoint) {
    this.sendOembedLoadedEvent(this.data.get('urlValue'))
    super.loadEndPoint(oEmbedEndPoint)
  }

  sendOembedLoadedEvent(embedUrl) {
    const event = new CustomEvent('oembed-loaded', { detail: { embedUrl: embedUrl } })
    window.dispatchEvent(event)
  }
}
