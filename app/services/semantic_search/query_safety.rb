# frozen_string_literal: true

module SemanticSearch
  # Content-safety gate for the "About these results" panel (summary text +
  # related topics): a query that mocks or derogatorily frames a person or a
  # group of people should get NO AI panel at all, not a hedged one.
  #
  # Unlike every other failure path in this feature - which degrades to
  # "show less" (no related topics, no citations) - this one degrades to
  # "show nothing" on ANY ambiguity, including a failed or errored
  # classification call. And unlike related-topic terms or cited documents
  # elsewhere in this feature, this judgment has no ground truth to check the
  # model's answer against - so, unusually for this codebase, the model's
  # judgment IS the mechanism rather than a candidate verified against real
  # data.
  module QuerySafety
    SYSTEM_PROMPT = <<~PROMPT.strip
      You are a content-safety check for a library archive search box. Given a search
      query, decide whether it's safe to generate an AI summary and topic suggestions in
      response to it.
      Answer NO if the query:
      - mocks, insults, or derogatorily frames a specific person or a group of people (by
        identity, demographic, physical trait, or other characteristic), or is otherwise
        abusive or harassing in intent - even if phrased as an innocuous-sounding question, OR
      - makes a vague, generic derogatory judgment about an unspecified group of people, on
        any axis (moral, intellectual, physical, social, hygienic, etc.) without naming
        a specific, identifiable historical event, period, group, or phenomenon.
      Answer YES for ordinary descriptive, historical, topical, or research queries -
      including ones about difficult historical subjects (genocide, war, slavery, internment,
      war crimes, etc.) - as long as they reference a specific, identifiable historical event,
      period, or group rather than a vague evaluative judgment about unspecified people.
      Respond with exactly one word: YES or NO.
    PROMPT

    module_function

    # @param query [String]
    # @return [Boolean] true only on an unambiguous "YES" - fails closed on
    #   any error, timeout, or unparseable response
    def safe?(query)
      return false if query.blank?

      Rails.cache.fetch(cache_key(query), expires_in: Settings.query_safety.cache_ttl) do
        classify(query)
      end
    rescue StandardError => e
      Rails.logger.warn("[SemanticSearch] query safety check failed: #{e.class}: #{e.message}")
      false
    end

    def classify(query)
      messages = [{ role: 'system', content: SYSTEM_PROMPT }, { role: 'user', content: query }]
      response = ChatCompletionService.new(timeout: Settings.query_safety.timeout)
                                      .complete(messages, model: Settings.query_safety.model, max_tokens: 5)
      response.strip.upcase == 'YES'
    end

    def cache_key(query)
      normalized_query = query.to_s.strip.downcase.gsub(/\s+/, ' ')
      "semantic_search/query_safety/#{Settings.query_safety.model}/#{normalized_query}"
    end
  end
end
