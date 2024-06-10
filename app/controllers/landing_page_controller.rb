# frozen_string_literal: true

# Controller for the landing page
class LandingPageController < ApplicationController
  include Blacklight::Configurable

  configure_blacklight do |config|
    config.header_component = LandingPage::HeaderComponent
    config.user_util_links_component = LandingPage::UserUtilLinksComponent
    config.logo_link = 'https://library.stanford.edu'
    config.full_width_layout = true

    # Configuration for autocomplete suggestor
    config.autocomplete_enabled = true
    config.autocomplete_path = 'suggest'
  end

  def index
    @hours = Settings.hours_locations.map { |hours_config| LibraryHours.from_config(hours_config) }
    @collection_count = site_collection_count
    @next_half_hour = TimeService.next_half_hour
  end

  private

  def site_collection_count
    Rails.cache.fetch('site_collection_count', expires_in: 1.hour) do
      search_service = Blacklight.repository_class.new(blacklight_config)
      query = search_service.search(
        q: 'level_ssim:Collection',
        rows: 1
      )
      query.response['numFound']
    end
  end
end
