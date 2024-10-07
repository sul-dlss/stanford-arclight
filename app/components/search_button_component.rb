# frozen_string_literal: true

# Subclasses Blacklight's SearchButtonComponent so we can set the
# button text to visually-hidden at all screen sizes
class SearchButtonComponent < Blacklight::SearchButtonComponent
  def call
    tag.button(class: 'btn btn-primary search-btn', type: 'submit', id: @id) do
      tag.span(@text, class: 'visually-hidden submit-search-text') +
        render(Blacklight::Icons::SearchComponent.new)
    end
  end
end
