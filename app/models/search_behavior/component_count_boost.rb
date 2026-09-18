# frozen_string_literal: true

module SearchBehavior
  # This SearchBuilder processor chain method adds a mild multiplicative boost
  # toward Collection-level docs with more catalogued sub-components, so a
  # broad topical query prefers the collection that actually holds a lot of
  # matching material over a single-item hit that only wins on BM25's title-
  # length normalization (see config/settings.yml `relevance` for the case
  # that prompted this).
  #
  # Uses total_component_count_is, which is already indexed (Indexer) but
  # otherwise unused in scoring. def() supplies 0 for any doc lacking the
  # field (everything below Collection level), making the boost a no-op
  # (factor 1.0) there.
  module ComponentCountBoost
    BROWSE_ALL_QUERIES = ['*', '*:*'].freeze

    def apply_component_count_boost(solr_parameters)
      divisor = Settings.relevance.component_count_boost_divisor.to_f
      return unless divisor.positive?
      return if blacklight_params[:q].blank? || BROWSE_ALL_QUERIES.include?(blacklight_params[:q])

      inject_component_count_boost(solr_parameters, component_count_boost_function(divisor))
    end

    private

    def component_count_boost_function(divisor)
      "sum(1,div(log(sum(def(total_component_count_is,0),1)),#{divisor}))"
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
