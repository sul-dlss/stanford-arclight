# frozen_string_literal: true

module Blacklight
  module Icons
    # The icon (right arrow) to display with the collection source information
    class CollectionSourceComponent < Blacklight::Icons::IconComponent
      self.svg = <<~SVG
        <svg xmlns="http://www.w3.org/2000/svg" width="24" height="24" fill="currentColor" class="bi bi-arrow-right-circle-fill" viewBox="0 0 16 16">
          <path d="M8 0a8 8 0 1 1 0 16A8 8 0 0 1 8 0M4.5 7.5a.5.5 0 0 0 0 1h5.793l-2.147 2.146a.5.5 0 0 0 .708.708l3-3a.5.5 0 0 0 0-.708l-3-3a.5.5 0 1 0-.708.708L10.293 7.5z"/>
        </svg>
      SVG
    end
  end
end
