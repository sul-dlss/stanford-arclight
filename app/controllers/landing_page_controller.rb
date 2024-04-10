# frozen_string_literal: true

# Controller for the landing page
class LandingPageController < ApplicationController
  def index
    @hours = Settings.hours_locations.map { |hours_config| LibraryHours.from_config(hours_config) }
    @collection_count = site_collection_count
  end

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
