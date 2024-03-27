# frozen_string_literal: true

# Display the document hierarchy as "breadcrumbs"
class BreadcrumbComponent < Arclight::BreadcrumbComponent
  def build_repository_link
    render RepositoryBreadcrumbComponent.new(document: @document)
  end
end
