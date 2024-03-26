# frozen_string_literal: true

# Render the breadcrumb hierarchy for a document
class BreadcrumbsHierarchyComponent < Arclight::BreadcrumbsHierarchyComponent
  def repository
    # Link to the search page, rather than the repository landing page.
    link_to(document.repository_config.name, helpers.repository_collections_path(document.repository_config))
  end
end
