# frozen_string_literal: true

# Component for rendering a prototype AI-generated summary above search results
class AiSummaryComponent < ViewComponent::Base
  def initialize(response:, query:)
    @response = response
    @query = query.presence || t('ai_summary.fallback_query')
    super()
  end

  def summary_text
    t('ai_summary.summary_html', query: @query)
  end

  def more_summary_text
    t('ai_summary.more_summary_html', query: @query)
  end

  def more_content_id
    "ai-summary-more-#{object_id}"
  end

  def source_documents
    @response.documents.first(3)
  end

  def render?
    @response.present? && !@response.empty?
  end
end
