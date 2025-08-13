# frozen_string_literal: true

# Component for rendering the collection unitid (call number)
class CollectionUnitidPillComponent < ViewComponent::Base
  def initialize(document:)
    @document = document
    super()
  end

  delegate :unitid, to: :@document

  def render?
    @document.collection?
  end
end
