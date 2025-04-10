# frozen_string_literal: true

module LandingPage
  # Provide an access card for the landing page
  class AccessCardComponent < ViewComponent::Base
    def initialize(key:)
      @key = key.to_s
      super
    end

    attr_reader :key

    def image
      image_tag "landing_page/#{key}.png", alt: '', class: 'img-fluid float-left p-2'
    end

    def heading
      I18n.t("landing_page.access_cards.#{key}.heading")
    end

    def entries
      I18n.t("landing_page.access_cards.#{key}.entries")
    end

    def request_button
      I18n.t("landing_page.access_cards.#{key}.request_html", default: '').html_safe
    end
  end
end
