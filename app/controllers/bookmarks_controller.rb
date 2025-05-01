# frozen_string_literal: true

# Override of Blacklight's BookmarksController to remove the group toggle.
class BookmarksController < CatalogController
  include Blacklight::Bookmarks

  configure_blacklight do |config|
    config.index.respond_to.csv = true
    config.view_config(:index).collection_actions.delete(:group_toggle)
    config.default_per_page = 50
  end
end
