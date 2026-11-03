# frozen_string_literal: true

# "Looking for more?" panel above the search results list: real, live results
# from SearchWorks and Exhibits for the current query, with a short
# AI-written blurb per system. See CrossSystemSearch::Suggestions for how
# it's built.
#
# Renders only when there is something to show, so a failed/slow/disabled
# lookup simply shows no panel (same defensive pattern as ResultsSummaryComponent).
class CrossSystemSuggestionsComponent < ViewComponent::Base
  def initialize(query:)
    @query = query
    super()
  end

  def render?
    sources.present?
  end

  def sources
    suggestions[:sources]
  end

  private

  def suggestions
    @suggestions ||= CrossSystemSearch::Suggestions.for(query: @query) || {}
  end
end
