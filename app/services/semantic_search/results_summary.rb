# frozen_string_literal: true

require 'erb'

module SemanticSearch
  # "About these results": a short AI-generated summary of the current search
  # results page, with citations to specific documents already on the page (no
  # extra Solr call) and a facet suggestion to narrow the result set.
  #
  # PROTOTYPE - deliberately simple: the facet suggestion is computed in plain
  # Ruby (never LLM-generated, so its count can never be wrong), and citations
  # are resolved server-side against a fixed candidate list rather than trusted
  # from the model's output, so the model can never emit an arbitrary link.
  module ResultsSummary
    # Fields eligible for the "narrow these results" suggestion, in preference
    # order when hit counts tie. Blacklight keys (not raw Solr field names) -
    # `response.aggregations` is keyed by both. Limited to descriptive/subject
    # facets (not e.g. repository or collection) so the suggestion narrows by
    # what the results are ABOUT, not where they happen to live.
    NARROW_FIELDS = { 'access_subjects' => 'Subject', 'places' => 'Place', 'names' => 'Name' }.freeze

    # Candidate documents are labeled A, B, C... for the model to cite.
    LABELS = ('A'..'Z').to_a.freeze

    CITATION_PATTERN = /\[\[([A-Z])\]\]/

    module_function

    # @param response [Blacklight::Solr::Response]
    # @param search_state [Blacklight::SearchState]
    # @return [Hash, nil] { summary_html:, narrow: { field_key:, field_label:, item: } or nil }
    def for(response:, search_state:)
      return nil unless applicable?(response, search_state)

      Rails.cache.fetch(cache_key(search_state), expires_in: Settings.results_summary.cache_ttl) do
        build(response, search_state)
      end
    rescue StandardError => e
      # A summary panel must never take down the results page.
      Rails.logger.warn("[SemanticSearch] results summary failed: #{e.class}: #{e.message}")
      nil
    end

    def applicable?(response, search_state)
      Settings.results_summary.enabled && search_state.query_param.present? && response.total.to_i.positive?
    end

    def build(response, search_state)
      candidates = candidate_documents(response)
      return nil if candidates.empty?

      summary_text = fetch_summary(search_state.query_param, response.total.to_i, candidates)
      return nil if summary_text.blank?

      { summary_html: render_citations(summary_text, candidates), narrow: narrow_suggestion(response, search_state) }
    end

    # `response.documents` is empty for a GROUPED response (?group=true) - the
    # actual hits live one level down, one representative doc per group.
    def candidate_documents(response)
      docs = response.grouped? ? response.groups.flat_map { |group| group.docs.first(1) } : response.documents
      LABELS.zip(docs.first(Settings.results_summary.max_documents)).to_h.compact
    end

    def fetch_summary(query, total, candidates)
      messages = [{ role: 'system', content: system_prompt },
                  { role: 'user', content: user_prompt(query, total, candidates) }]
      ChatCompletionService.new(timeout: Settings.results_summary.timeout)
                           .complete(messages, model: Settings.results_summary.model, max_tokens: 220)
                           .strip
    end

    # rubocop:disable Metrics/MethodLength
    def system_prompt
      <<~PROMPT.strip
        You write short, factual summaries for a library finding-aid search results page.
        Rules:
        - Only state facts explicitly given to you. Never invent counts, dates, names, or other facts.
        - When you mention one of the labeled results given to you, put its exact marker immediately
          after it, like this: Yamato Ichihashi papers[[B]]. Only use markers you were given - never
          invent a letter or use one that was not listed.
        - Write 2-3 plain sentences. No headings, no lists, no HTML or markdown.
        - If there isn't enough information to say something specific, write a shorter, more general
          summary rather than guessing.
      PROMPT
    end
    # rubocop:enable Metrics/MethodLength

    def user_prompt(query, total, candidates)
      lines = ["Search query: \"#{query}\"", "Total matching results: #{total}", '', 'Results you may cite:']
      candidates.each { |label, doc| lines << "#{label}. #{describe(doc)}" }
      lines.join("\n")
    end

    def describe(doc)
      parts = [title_of(doc)]
      parts << "collection: #{collection_title_of(doc)}" if collection_title_of(doc).present?
      parts << "repository: #{repository_of(doc)}" if repository_of(doc).present?
      parts << 'digitized' if digitized?(doc)
      parts.join(', ')
    end

    def title_of(doc)
      Array(doc['normalized_title_ssm']).first.presence || Array(doc['title_tesim']).first.presence || doc.id
    end

    def collection_title_of(doc)
      Array(doc['collection_title_tesim']).first.presence
    end

    def repository_of(doc)
      Array(doc['repository_ssim']).first
    end

    def digitized?(doc)
      Array(doc['has_online_content_ssim']).include?(true) || doc['has_online_content_ssim'] == true
    end

    # HTML-escape the ENTIRE model response first, then substitute only our own
    # well-formed <sup> links for recognized [[X]] markers. The model's raw
    # output is never trusted as HTML - an unrecognized or hallucinated marker
    # is silently dropped rather than rendered.
    def render_citations(text, candidates)
      escaped = ERB::Util.html_escape(text)
      escaped.gsub(CITATION_PATTERN) do
        doc = candidates[Regexp.last_match(1)]
        doc ? citation_link(Regexp.last_match(1), doc) : ''
      end.html_safe # rubocop:disable Rails/OutputSafety
    end

    # data-turbo-frame="_top": this link renders INSIDE the results-summary
    # turbo-frame, so without it Turbo would scope the navigation to that frame
    # instead of loading the document page as a normal full-page visit.
    def citation_link(label, doc)
      path = Rails.application.routes.url_helpers.solr_document_path(doc.id)
      %(<sup><a href="#{ERB::Util.html_escape(path)}" data-turbo-frame="_top">#{label}</a></sup>)
    end

    # Highest-count value from an allowlisted facet field that isn't already
    # applied as a filter. Never LLM-generated - just today's top facet count.
    def narrow_suggestion(response, search_state)
      candidates = NARROW_FIELDS.filter_map do |field_key, field_label|
        narrow_candidate(response, search_state, field_key, field_label)
      end
      candidates.max_by { |candidate| candidate[:item].hits.to_i }
    end

    def narrow_candidate(response, search_state, field_key, field_label)
      return nil if already_filtered?(search_state, field_key)

      aggregation = response.aggregations[field_key]
      item = aggregation&.items&.max_by { |i| i.hits.to_i }
      return nil unless item

      { field_key: field_key, field_label: field_label, item: item }
    end

    def already_filtered?(search_state, field_key)
      Array(search_state.params.dig(:f, field_key)).any?
    end

    def cache_key(search_state)
      normalized_query = search_state.query_param.to_s.strip.downcase.gsub(/\s+/, ' ')
      filters = search_state.params[:f].to_h.sort.to_s
      "semantic_search/results_summary/#{Settings.results_summary.model}/#{normalized_query}/#{filters}"
    end
  end
end
