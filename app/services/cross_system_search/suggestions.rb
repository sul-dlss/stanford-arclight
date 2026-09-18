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
  #
  # Also shares ResultsSummary's content-safety gate (SemanticSearch::QuerySafety):
  # the per-system blurb is the same kind of free-text characterization that
  # gate exists to protect against, so a query judged unsafe gets no panel at
  # all here either, not just a version with the blurb stripped.
  module Suggestions
    # Relevance judgment the model emits alongside (not embedded in) the free-
    # text blurb - see system_prompt/parse_summary_lines. Deliberately a
    # separate, tightly-constrained field rather than an exact-phrase match on
    # the sentence itself: a model can honestly convey "this doesn't really
    # relate to the query" in its own words without hitting a literal required
    # string, which silently defeated the earlier phrase-matching version (a
    # real query surfaced high-count, topically-unrelated results tagged
    # "Strong match" because the model described the mismatch honestly instead
    # of emitting the exact recognized phrase).
    RELEVANCE_VALUES = %w[RELATED UNRELATED].freeze

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
      Settings.cross_system_search.enabled && query.present? && query_safe?(query)
    end

    # See SemanticSearch::QuerySafety - fails closed, so disabling it (dev/test
    # only) is the one way to skip the check rather than an error suppressing it.
    def query_safe?(query)
      return true unless Settings.query_safety.enabled

      SemanticSearch::QuerySafety.safe?(query)
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

    # A system with zero real results has nothing worth showing - treated the
    # same as a system that failed to respond, so it's dropped rather than
    # rendered as an empty "no results" stub. If BOTH systems drop out this
    # way, fetch_sources returns empty and build's own check hides the whole
    # panel, not just one system's section.
    def source_from(query, system, result)
      return nil unless result
      return nil if result.total.to_i.zero?

      build_source(query, system, result)
    end

    def build_source(query, system, result)
      { label: system.label, total: result.total, tier: tier_for(result.total),
        doc: system.doc_view.call(result.docs.first), search_url: system.search_url.call(query),
        sample: result.docs.filter_map { |doc| system.describe_for_prompt.call(doc) } }
    end

    def tier_for(total)
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
        format: "<Label>:: <RELATED or UNRELATED>:: <sentence>" - one line per system, in the order
        given, nothing else.
        The middle field is a relevance judgment, exactly the word RELATED or UNRELATED: write
        RELATED if the sample genuinely relates to the search query's topic, or UNRELATED if the
        sample only shares incidental keywords/stopwords with the query without real topical
        relevance (e.g. a natural-language query like "how do you make candy" matching only on
        "how/do/you/make", or a person's name matching documents that merely contain those words).
        Judge this honestly and independently of how you phrase the sentence.
        Rules:
        - Base the sentence ONLY on the sample given - synthesize across it (formats, eras, topics),
          using words like "including" or "such as" rather than claiming it describes every result.
        - Never invent or restate a specific count as a fact - the real total is shown separately by
          the app. Do not state a number.
        - Write the sentence honestly either way - if UNRELATED, describe what the sample actually
          contains rather than pretending it relates to the query.
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
        parsed_line = parsed[source[:label]]
        source[:tier] = :low_confidence if parsed_line && parsed_line[:relevance] == 'UNRELATED'
        source[:blurb_html] = sanitize(parsed_line && parsed_line[:sentence])
      end
    end

    # A line that doesn't match the required "<Label>:: <RELATED|UNRELATED>::
    # <sentence>" shape - wrong relevance word, missing field, reworded by the
    # model - is dropped rather than guessed at, same as an unrecognized
    # citation marker elsewhere in this feature: that source just gets no
    # blurb (see apply_blurbs!) rather than a mismatched or invented one.
    def parse_summary_lines(summary)
      summary.each_line.filter_map do |line|
        match = line.match(/\A\s*([^:]+)::\s*(RELATED|UNRELATED)::\s*(.+?)\s*\z/i)
        next unless match

        label, relevance, sentence = match.captures
        [label, { relevance: relevance.upcase, sentence: sentence }]
      end.to_h
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
