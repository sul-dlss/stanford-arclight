# frozen_string_literal: true

# Renders paging and per-page controls for the collection's component list
class DocumentCollectionControlsComponent < ViewComponent::Base
  def initialize(response:, search_state:, blacklight_config:, params:)
    @response = response
    @search_state = search_state
    @blacklight_config = blacklight_config
    @params = params
    super
  end

  def per_page_dropdown
    render Blacklight::Search::PerPageComponent.new(search_state: reset_search_state, blacklight_config:, response:)
  end

  def compact_paging
    render Blacklight::Response::PaginationComponent.new(
      response: response,
      theme: :blacklight_compact,
      page_entries_info: helpers.page_entries_info(response),
      role: nil,
      html: { aria: {} }
    )
  end

  def render?
    helpers.show_pagination?(response) && params[:paginate]
  end

  private

  attr_reader :response, :search_state, :blacklight_config, :params

  def reset_search_state
    search_state.reset_search(select_params)
  end

  def select_params
    params.permit(:key, :paginate).slice(:key, :paginate)
  end
end
