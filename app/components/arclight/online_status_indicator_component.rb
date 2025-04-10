# frozen_string_literal: true

# Overrides Arclight's OnlineStatusIndicatorComponent to replace with a custom template that includes our tooltip
module Arclight
  # Render an online status indicator for a document
  class OnlineStatusIndicatorComponent < Blacklight::Component
    def initialize(document:, **)
      @document = document
      super
    end

    def render?
      @document.online_content?
    end

    def icon_with_tooltip
      icon = <<~HTML
        <span class="al-online-content-icon me-2" data-bs-toggle="tooltip" data-bs-placement="top" data-bs-html="true" data-bs-title="Includes digital content">
            #{helpers.blacklight_icon(:online)}
        </span>
      HTML
      icon.html_safe # rubocop:disable Rails/OutputSafety
    end
  end
end
