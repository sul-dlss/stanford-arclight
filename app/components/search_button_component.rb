# frozen_string_literal: true

# Subclasses Blacklight's SearchButtonComponent so we can set the
# button text to visually-hidden at all screen sizes
class SearchButtonComponent < Blacklight::SearchButtonComponent
  def call
    tag.div(class: 'search-btn-wrapper rounded-end d-flex') do
      tag.button(class: 'btn btn-primary search-btn', type: 'submit', id: @id) do
        # Text visible only on md and larger screens
        tag.span(t('search.search_bar_button'), class: 'd-none d-md-flex') +
          # Icon visible only on smaller screens
          tag.span(render(Blacklight::Icons::SearchComponent.new), class: 'd-md-none')
      end
    end
  end
end
