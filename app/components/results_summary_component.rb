# frozen_string_literal: true

# "About these results" panel above the search results list: an AI-generated
# summary of the current result set with citations, plus related-topic
# suggestions. See SemanticSearch::ResultsSummary for how it's built.
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

  def related_topics
    summary[:related_topics] || []
  end

  # A fresh topic browse, not a narrowing of the current search - the term
  # came from the query text alone, so it isn't guaranteed to overlap with
  # this search's current results (see SemanticSearch::ResultsSummary).
  def related_topic_href(term)
    helpers.search_action_path(f: { SemanticSearch::ResultsSummary::RELATED_TOPICS_FIELD => [term] })
  end

  private

  def summary
    @summary ||= SemanticSearch::ResultsSummary.for(response: @response, search_state: @search_state) || {}
  end
end
