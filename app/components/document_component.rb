# frozen_string_literal: true

# Inherit from Arclight::DocumentComponent to create a custom document component
# Conditionally render different metadata depending on component level
class DocumentComponent < Arclight::DocumentComponent
  def document_body_component
    render component.new(
      document: document,
      presenter: presenter,
      metadata_partials: partials
    )
  end

  def partials
    document.collection? ? metadata_partials : component_metadata_partials
  end

  def component
    document.collection? ? DocumentBodyCollectionComponent : DocumentBodyComponent
  end
end
