import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  connect() {
    this.element.addEventListener('submit', this.handleSubmit.bind(this));
  }

  handleSubmit(event) {
    event.preventDefault();

    const selectElement = this.element.querySelector('[id^="within_collection"]');
    const levelFacet = this.element.querySelector('input[name="f[level][]"]');
    const groupByCollection = this.element.querySelector('input[name="group"]');

    // See https://github.com/sul-dlss/stanford-arclight/issues/544
    // We default to grouping results by collection, but if the user
    // is searching within a collection or limits their results to
    // collections only then default to all results.
    if (selectElement.value || levelFacet?.value == 'Collection') {
      groupByCollection?.remove();
    }

    this.element.submit();
  }
}
