# frozen_string_literal: true

# Renders a single compact result row for display within a grouped search result.
# Intentionally lightweight: icon, title link, container, and one highlight snippet.
# Bookmark form, abstract/scope, and breadcrumbs are omitted — the group header
# already provides collection context.
class GroupedSearchResultComponent < ViewComponent::Base
  def initialize(document:)
    @document = document
    super()
  end

  def icon
    helpers.blacklight_icon helpers.document_or_parent_icon(@document)
  end

  def containers
    @document.containers.join(', ')
  end

  def highlight
    @document.highlights&.first
  rescue TypeError, NoMethodError
    nil
  end
end
