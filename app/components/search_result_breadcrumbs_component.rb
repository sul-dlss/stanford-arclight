# frozen_string_literal: true

# Render the breadcrumbs for a search result document
class SearchResultBreadcrumbsComponent < Arclight::SearchResultBreadcrumbsComponent
  def breadcrumbs
    offset = grouped? ? 2 : 0

    BreadcrumbComponent.new(document:, count: breadcrumb_count, offset:)
  end
end
