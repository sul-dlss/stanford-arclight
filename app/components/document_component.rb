# frozen_string_literal: true

# Inherit from Arclight::DocumentComponent to create a custom document component
# Conditionally render different metadata depending on component level
class DocumentComponent < Arclight::DocumentComponent
  # rubocop:disable Metrics/MethodLength
  def document_body_component
    if document.collection?
      # Render the collection metadata component
      render DocumentBodyCollectionComponent.new(
        document: document,
        presenter: presenter,
        metadata_partials: metadata_partials
      )
    else
      # Render the general/component-level document metadata component
      render DocumentBodyComponent.new(
        document: document,
        presenter: presenter,
        component_metadata_partials: component_metadata_partials
      )
    end
    # rubocop:enable Metrics/MethodLength
  end
end
