# frozen_string_literal: true

module SearchBehavior
  # Boosts Collection-level docs with more catalogued sub-components, so a
  # broad topical query favors the collection that actually holds a lot of
  # matching material over a single item that only wins on BM25's title-
  # length normalization.
  #
  # Only applies to collections whose own relevance already clears MIN_SCORE.
  # Otherwise a huge collection that matches the query incidentally - one
  # component title buried among thousands of others - can out-boost a small
  # collection that's genuinely about the query.
  module ComponentCountBoost
    BROWSE_ALL_QUERIES = ['*', '*:*'].freeze

    DIVISOR = 6
    MIN_SCORE = 20

    # Below this size the multiplier tops out around 1.65x (1 + ln(51)/DIVISOR),
    # too small to flip a ranking on its own, so these collections skip the
    # relevance check and get boosted unconditionally.
    RELEVANCE_CHECK_FLOOR = 50

    def apply_component_count_boost(solr_parameters)
      return if blacklight_params[:q].blank? || BROWSE_ALL_QUERIES.include?(blacklight_params[:q])

      inject_component_count_boost(solr_parameters, component_count_boost_function)
    end

    private

    def component_count_boost_function
      size_boost = "sum(1,div(log(sum(def(total_component_count_is,0),1)),#{DIVISOR}))"

      # boost=1 and bq='' both prevent the inner query from picking up the outer
      # request's own boost/bq params, causing a recursion error.
      relevance_check = "gt(query({!edismax v=$q boost=1 bq=''}),#{MIN_SCORE})"
      "if(gt(def(total_component_count_is,0),#{RELEVANCE_CHECK_FLOOR})," \
        "if(#{relevance_check},#{size_boost},1)," \
        "#{size_boost})"
    end

    # Hybrid mode carries the lexical query as a nested `edismax` query inside
    # json.query (see SearchBehavior::SemanticQuery#apply_rerank_hybrid) -
    # only that query parser recognizes a `boost` local param there. Anywhere
    # else (plain keyword q, or no lexical component at all e.g. pure vector
    # mode) falls back to the top-level `boost` request param, which edismax
    # honors directly and which Solr otherwise just ignores.
    def inject_component_count_boost(solr_parameters, boost_function)
      lexical_query = solr_parameters.dig(:json, :query, :bool, :should, 0, :edismax)
      if lexical_query
        lexical_query[:boost] = boost_function
      else
        solr_parameters[:boost] = boost_function
      end
    end
  end
end
