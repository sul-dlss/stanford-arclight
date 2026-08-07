import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  connect() {
    this.beginInput = this.element.querySelector('input[name="range[date_range][begin]"]');
    this.endInput = this.element.querySelector('input[name="range[date_range][end]"]');
    this.beginInput.addEventListener('input', event => this.updateInputRequiredState(event));
    this.endInput.addEventListener('input', event => this.updateInputRequiredState(event));
  }

  updateInputRequiredState(event) {
    const bothEmpty = this.beginInput.value === '' && this.endInput.value === ''
  
    // Allow the user to submit an empty range to clear the search, otherwise require both bounds.
    // If blacklight_range_limit is updated or our config changes, review if this and the override
    // to range_form_component.html.erb are still necessary.
    if (bothEmpty) {
      this.beginInput.removeAttribute('required');
      this.endInput.removeAttribute('required');
    } else {
      this.beginInput.setAttribute('required', '');
      this.endInput.setAttribute('required', '');
    }
  }
}