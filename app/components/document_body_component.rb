# frozen_string_literal: true

# Component-level metadata for the document body
# Also responsible for rendering embed content
class DocumentBodyComponent < ViewComponent::Base
  def initialize(document:, presenter:, component_metadata_partials:)
    @document = document
    @presenter = presenter
    @component_metadata_partials = component_metadata_partials
    super
  end

  attr_reader :document, :presenter, :component_metadata_partials

  def embed_html
    view_context.embed
  end
end
