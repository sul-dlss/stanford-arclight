export default function initializeAutocompleteToggle() {
  const searchField = document.querySelector('#search_field');
  const autocomplete = document.querySelector('.search-autocomplete-wrapper');
  const autocompleteSrc = autocomplete?.src;

  // Update the autocomplete display based on the selected search field value
  function updateAutocompleteDisplay() {
    const selectedSearchField = searchField.value;

    if (selectedSearchField === "keyword") {
      autocomplete.setAttribute("src", autocompleteSrc)
    } else {
      // Remove the src attribute to hide the autocomplete
      autocomplete.removeAttribute("src");
    }
  }

  if (searchField && autocomplete) {
    searchField.addEventListener('change', updateAutocompleteDisplay);
  }
}
