# frozen_string_literal: true

require 'erb'

module CrossSystemSearch
  # "Looking for more?" panel: real results fetched live, server-side, from
  # SearchWorks and Exhibits for the current query. Each source shows its
  # real top result as an actual result (a title you can click), plus an
  # AI-written summary of the KINDS of material you'd find if you followed
  # the "see all results" link - not a caption on just that one item.
  #
  # Same house rule as SemanticSearch::ResultsSummary: counts, titles, and
  # links are real data from the source system, never LLM-generated - the
  # model only characterizes a real sample it was actually given.
  module Suggestions
    # Exact-phrase escape hatch (same pattern as the zero-total rule below):
    # lets the model flag topical mismatch - e.g. a natural-language query
    # like "how do you make candy" matching only on stopwords - without
    # inventing a false unifying theme. Downgrades the tier deterministically
    # (see apply_blurbs!); the phrase itself is never trusted beyond that.
    UNRELATED_PHRASE = 'Results may not be closely related to this query.'

    System = Struct.new(:label, :client_class, :doc_view, :search_url, :describe_for_prompt)

    # Hardcoded to these two systems for now rather than a generic registry;
    # add a third by adding a row here.
    SYSTEMS = [
      System.new('SearchWorks', SearchworksClient, SearchworksClient.method(:doc_view),
                 SearchworksClient.method(:search_url), SearchworksClient.method(:describe_for_prompt)),
      System.new('Exhibits', ExhibitsClient, ExhibitsClient.method(:doc_view),
                 ExhibitsClient.method(:search_url), ExhibitsClient.method(:describe_for_prompt))
    ].freeze

    module_function

    # @param query [String]
    # @return [Hash, nil] { sources: [{ label:, total:, tier:, doc:, blurb_html:, search_url: }, ...] }
    def for(query:)
      return nil unless applicable?(query)

      Rails.cache.fetch(cache_key(query), expires_in: Settings.cross_system_search.cache_ttl) do
        build(query)
      end
    rescue StandardError => e
      # A "looking for more?" panel must never take down the results page.
      Rails.logger.warn("[CrossSystemSearch] suggestions failed: #{e.class}: #{e.message}")
      nil
    end

    def applicable?(query)
      Settings.cross_system_search.enabled && query.present?
    end

    def build(query)
      sources = fetch_sources(query)
      return nil if sources.empty?

      summary = fetch_summary(query, sources)
      return nil if summary.blank?

      apply_blurbs!(sources, summary)
      { sources: sources }
    end

    # Each system's request runs on its own thread with its own short
    # timeout, so the slower of the two bounds wall time, not the sum.
    def fetch_sources(query)
      threads = SYSTEMS.map { |system| search_thread(query, system) }
      threads.filter_map { |thread| source_from(query, *thread.value) }
    end

    def search_thread(query, system)
      rows = Settings.cross_system_search.rows
      timeout = Settings.cross_system_search.timeout
      Thread.new { [system, system.client_class.new(timeout: timeout).search(query, rows: rows)] }
    end

    def source_from(query, system, result)
      return nil unless result

      { label: system.label, total: result.total, tier: tier_for(result.total),
        doc: system.doc_view.call(result.docs.first), search_url: system.search_url.call(query),
        sample: result.docs.filter_map { |doc| system.describe_for_prompt.call(doc) } }
    end

    def tier_for(total)
      return :no_match if total.to_i.zero?
      return :strong_match if total.to_i >= Settings.cross_system_search.strong_match_min

      :worth_a_look
    end

    def fetch_summary(query, sources)
      messages = [{ role: 'system', content: system_prompt }, { role: 'user', content: user_prompt(query, sources) }]
      model = Settings.cross_system_search.model
      SemanticSearch::ChatCompletionService.new(timeout: Settings.cross_system_search.timeout)
                                           .complete(messages, model: model, max_tokens: 120)
                                           .strip
    end

    # rubocop:disable Metrics/MethodLength
    def system_prompt
      <<~PROMPT.strip
        You write a one-sentence preview of the KINDS of material a user would find if they
        clicked through to see all real results in another library system - not a caption on one
        specific item (a top result is shown separately, already rendered, so do not just restate
        its title). You are given a small SAMPLE of real results already fetched from each system
        (never the full set). For EACH system listed, respond with exactly one line in this exact
        format: "<Label>:: <sentence>" - one sentence (under 25 words), one line per system, in the
        order given, nothing else.
        Rules:
        - Base the sentence ONLY on the sample given - synthesize across it (formats, eras, topics),
          using words like "including" or "such as" rather than claiming it describes every result.
        - Never invent or restate a specific count as a fact - the real total is shown separately by
          the app. Do not state a number.
        - If a system's real total is zero, the sentence MUST be exactly "No related results found."
        - If the sample doesn't look topically related to the search query - e.g. a natural-language
          query where the sample only shares common words (how/do/you/make) rather than real
          relevance - do NOT invent a unifying theme. The sentence MUST instead be exactly
          "#{UNRELATED_PHRASE}"
        - Write in a neutral, third-person voice. No headings, no lists, no markdown, no citations.
      PROMPT
    end
    # rubocop:enable Metrics/MethodLength

    def user_prompt(query, sources)
      lines = ["Search query: \"#{query}\"", '', 'Systems, in the order to respond in:']
      sources.each { |source| lines << describe(source) }
      lines.join("\n")
    end

    def describe(source)
      sample_desc = source[:sample].present? ? "sample of real results: #{source[:sample].join('; ')}" : 'no results'
      "#{source[:label]}: real total #{source[:total]}, #{sample_desc}"
    end

    def apply_blurbs!(sources, summary)
      parsed = parse_summary_lines(summary)
      sources.each do |source|
        text = parsed[source[:label]]
        source[:tier] = :low_confidence if text&.strip == UNRELATED_PHRASE
        source[:blurb_html] = sanitize(text)
      end
    end

    def parse_summary_lines(summary)
      summary.each_line.filter_map { |line| line.match(/\A\s*([^:]+)::\s*(.+?)\s*\z/)&.captures }.to_h
    end

    # The model's raw output is never trusted as HTML (same rule as
    # SemanticSearch::ResultsSummary) - there's no markup to substitute here
    # since the result link itself is rendered separately by the view.
    def sanitize(text)
      return nil if text.blank?

      ERB::Util.html_escape(text).html_safe # rubocop:disable Rails/OutputSafety
    end

    def cache_key(query)
      normalized_query = query.to_s.strip.downcase.gsub(/\s+/, ' ')
      "cross_system_search/suggestions/#{Settings.cross_system_search.model}/v4/#{normalized_query}"
    end
  end
end
