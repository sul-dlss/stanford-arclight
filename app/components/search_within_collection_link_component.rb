# frozen_string_literal: true

class SearchWithinCollectionLinkComponent < Blacklight::Component
  def initialize(document:, **)
    @document = document
    super()
  end

  def render?
    !within_collection_search? && top_level_collection?
  end

  def current_query
    helpers.search_state.query_param
  end

  def search_url
    helpers.search_catalog_path(
      q: current_query,
      search_field: 'within_collection',
      f: { collection: [Array(@document['collection_ssim']).first] }
    )
  end

  private

  def within_collection_search?
    search_field = helpers.search_state.params[:search_field] || helpers.search_state.params['search_field']
    search_field == 'within_collection'
  end

  def top_level_collection?
    levels = Array(@document['level_ssm']) + Array(@document['level_ssim'])
    levels.include?('collection') && @document['parent_ssim'].blank?
  end
end
