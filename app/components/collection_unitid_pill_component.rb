# frozen_string_literal: true

# Component for rendering information about the collection source
class CollectionUnitidPillComponent < ViewComponent::Base
  def initialize(document:)
    @document = document
    super
  end

  delegate :unitid, to: :@document

  def render?
    @document.collection?
  end
end
