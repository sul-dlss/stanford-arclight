# frozen_string_literal: true

# Collection-level document display with metadata and UsingTheseMaterials
class DocumentBodyCollectionComponent < ViewComponent::Base
  def initialize(document:, presenter:, metadata_partials:)
    @document = document
    @presenter = presenter
    @metadata_partials = metadata_partials
    super
  end

  attr_reader :document, :presenter, :metadata_partials
end
