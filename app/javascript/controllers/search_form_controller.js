import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  connect() {
    this.element.addEventListener('submit', this.handleSubmit.bind(this));
  }

  handleSubmit(event) {
    event.preventDefault();

    const selectElement = this.element.querySelector('[id^="within_collection"]');
    const groupByCollection = this.element.querySelector('input[name="group"]');

    // See https://github.com/sul-dlss/stanford-arclight/issues/544
    // We default to grouping results by collection, but if the user
    // is searching within a collection then default to all results.
    if (selectElement.value) {
      groupByCollection?.remove();
    }

    this.element.submit();
  }
}
