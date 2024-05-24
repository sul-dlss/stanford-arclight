# frozen_string_literal: true

module LandingPage
  # Provides a header with a masthead
  class HeaderComponent < Arclight::HeaderComponent
    def masthead
      render LandingPage::MastheadComponent.new
    end
  end
end
