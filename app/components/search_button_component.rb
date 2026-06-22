# frozen_string_literal: true

# Override the default Blacklight SearchButtonComponent to use the
# design system's search button markup.
class SearchButtonComponent < Blacklight::SearchButtonComponent
  def call
    tag.button(class: 'btn btn-primary search-btn', type: 'submit', id: @id) do
      tag.span(@text, class: 'submit-search-text')
    end
  end
end
