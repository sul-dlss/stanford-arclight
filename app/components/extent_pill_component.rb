# frozen_string_literal: true

# Component for rendering the extent information
class ExtentPillComponent < ViewComponent::Base
  def initialize(document:, compact: false)
    @document = document
    @compact = compact
    super()
  end

  def extents
    @document.extent.join('; ').truncate_words(6, separator: /[\s,;]/)
  end

  def render?
    !@compact && @document.extent.any?
  end
end
