# frozen_string_literal: true

# Component-level metadata for the document body
# Also responsible for rendering embed content
class DocumentBodyComponent < ViewComponent::Base
  def initialize(document:, presenter:, metadata_partials:, embed:)
    @embed = embed
    @document = document
    @presenter = presenter
    @metadata_partials = metadata_partials
    super()
  end

  attr_reader :document, :presenter, :metadata_partials, :embed
end
