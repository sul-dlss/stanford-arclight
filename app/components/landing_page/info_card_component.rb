# frozen_string_literal: true

module LandingPage
  # Provide an info card for the landing page
  class InfoCardComponent < ViewComponent::Base
    def initialize(key:)
      @key = key.to_s
      super
    end

    def image
      image_tag "landing_page/#{@key}.png", alt: '', class: 'img-fluid float-left'
    end

    def heading
      I18n.t("landing_page.info_cards.#{@key}.heading")
    end

    def description
      I18n.t("landing_page.info_cards.#{@key}.description")
    end

    def button
      I18n.t("landing_page.info_cards.#{@key}.button_html", default: '').html_safe
    end
  end
end
