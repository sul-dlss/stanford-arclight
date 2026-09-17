# frozen_string_literal: true

require 'erb'

module SemanticSearch
  # "About these results": a short AI-generated summary of the current search
  # results page, with citations to specific documents already on the page (no
  # extra Solr call) and related-topic suggestions.
  #
  # PROTOTYPE - deliberately simple: citations are resolved server-side against
  # a fixed candidate list rather than trusted from the model's output, so the
  # model can never emit an arbitrary link. Related topics are a nearest-
  # neighbor lookup against the REAL subject vocabulary already in the index
  # (SubjectVocabulary), not LLM-generated, so a suggested topic can never be
  # one that doesn't exist in the archive - though unlike the old aggregation-
  # based narrow suggestion, it is NOT guaranteed to overlap with the CURRENT
  # result set, since it's found from the query text alone. That's why it
  # links to a fresh topic browse rather than adding a facet to this search.
  module ResultsSummary
    # Blacklight facet config key (not the raw Solr field name) for related
    # topic links - `search_action_path(f: { RELATED_TOPICS_FIELD => [term] })`.
    RELATED_TOPICS_FIELD = 'access_subjects'
    RELATED_TOPICS_LIMIT = 5

    # Candidate documents are labeled A, B, C... for the model to cite.
    LABELS = ('A'..'Z').to_a.freeze

    CITATION_PATTERN = /\[\[([A-Z])\]\]/

    module_function

    # @param response [Blacklight::Solr::Response]
    # @param search_state [Blacklight::SearchState]
    # @return [Hash, nil] { summary_html:, related_topics: Array<String> }
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

      related_topics = SemanticSearch::SubjectVocabulary.related_terms(search_state.query_param,
                                                                       limit: RELATED_TOPICS_LIMIT)
      { summary_html: render_citations(summary_text, candidates), related_topics: related_topics }
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
        You write short summaries for a library finding-aid search results page.
        Rules:
        - Never invent counts, dates, names, or other hard facts beyond what is given to you.
        - You MAY characterize the general nature of the material - its formats (photographs,
          audio recordings, correspondence, administrative records, etc.), era, and tone (e.g.
          lighthearted, official, personal) - by drawing reasonable inferences from the titles,
          extents, and descriptions given. Say so in general terms rather than asserting it as a
          fact about every result.
        - When you mention one of the labeled results given to you, refer to it by its title or a
          short description of it - NEVER by its letter (do not write "result B" or similar) - and
          put its exact marker immediately after, like this: Yamato Ichihashi papers[[B]]. Only use
          markers you were given - never invent a letter or use one that was not listed.
        - Write 2-3 plain sentences. No headings, no lists, no HTML or markdown.
        - If there isn't enough information to say something specific, write a shorter, more general
          summary rather than guessing.
        - Write in a neutral, third-person voice describing the results themselves. Never use "I" or
          "we" statements (e.g. "I found", "we can see", "I couldn't determine").
        - You MAY characterize how closely results relate to the search query and to what degree -
          e.g. note when top-ranked results are a direct/strong match versus when lower-ranked
          results relate only loosely or thematically. Base this on the rank order and the titles/
          descriptions given, not on the rank number itself (never state a rank number in the
          summary - it is for your judgment only).
      PROMPT
    end
    # rubocop:enable Metrics/MethodLength

    def user_prompt(query, total, candidates)
      lines = ["Search query: \"#{query}\"", "Total matching results: #{total}", '',
               'Results you may cite, in relevance rank order (rank 1 = the strongest match):']
      candidates.each_with_index { |(label, doc), index| lines << "#{label}. (rank #{index + 1}) #{describe(doc)}" }
      lines.join("\n")
    end

    def describe(doc)
      parts = [title_of(doc)]
      parts << "collection: #{collection_title_of(doc)}" if collection_title_of(doc).present?
      parts << "repository: #{repository_of(doc)}" if repository_of(doc).present?
      parts << "format/extent: #{extent_of(doc)}" if extent_of(doc).present?
      parts << 'digitized' if digitized?(doc)
      parts.join(', ')
    end

    def title_of(doc)
      Array(doc['normalized_title_ssm']).first.presence || Array(doc['title_tesim']).first.presence || doc.id
    end

    def collection_title_of(doc)
      Array(doc['collection_title_tesim']).first.presence
    end

    # The closest thing to a "format" signal already indexed (e.g. "2
    # audiocassette(s)", "636 box(es)") - lets the model characterize the
    # material's nature without us needing a dedicated genre/format field.
    def extent_of(doc)
      Array(doc['extent_ssm']).first.presence
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

    def cache_key(search_state)
      normalized_query = search_state.query_param.to_s.strip.downcase.gsub(/\s+/, ' ')
      filters = search_state.params[:f].to_h.sort.to_s
      "semantic_search/results_summary/#{Settings.results_summary.model}/#{normalized_query}/#{filters}"
    end
  end
end
