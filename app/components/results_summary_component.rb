# frozen_string_literal: true

# "About these results" panel above the search results list: an AI-generated
# summary of the current result set with citations, plus a facet suggestion to
# narrow the results. See SemanticSearch::ResultsSummary for how it's built.
#
# Renders only when there is a summary to show, so a failed/slow/disabled
# lookup simply shows no panel (same defensive pattern as RelatedCollectionsComponent).
class ResultsSummaryComponent < ViewComponent::Base
  def initialize(response:, search_state:)
    @response = response
    @search_state = search_state
    super()
  end

  def render?
    summary.present?
  end

  def summary_html
    summary[:summary_html]
  end

  def narrow
    summary[:narrow]
  end

  def narrow_href
    return nil unless narrow

    helpers.search_action_path(@search_state.add_facet_params_and_redirect(narrow[:field_key], narrow[:item]))
  end

  private

  def summary
    @summary ||= SemanticSearch::ResultsSummary.for(response: @response, search_state: @search_state) || {}
  end
end
