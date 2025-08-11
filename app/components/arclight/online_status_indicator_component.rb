# frozen_string_literal: true

# Overrides Arclight's OnlineStatusIndicatorComponent to replace with a custom template that includes our popover
module Arclight
  # Render an online status indicator for a document
  class OnlineStatusIndicatorComponent < Blacklight::Component
    def initialize(document:, **)
      @document = document
      super()
    end

    def render?
      @document.online_content?
    end

    def icon_with_popover
      render OnlineContentPopoverComponent.new
    end
  end
end
