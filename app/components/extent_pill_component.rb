# frozen_string_literal: true

# Component for rendering information about the collection source
class ExtentPillComponent < ViewComponent::Base
  def initialize(document:, compact: false)
    @document = document
    @compact = compact
    super
  end

  attr_reader :document

  def extents
    @document.extent.map { |e| e.truncate(45) }
  end

  def render?
    !@compact
  end
end
