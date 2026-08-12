# frozen_string_literal: true

# Dev/stage-only panel for live relevance tuning of semantic search. Rendered
# above search results (via catalog/_search_header) only when both semantic
# query and the tuning flag are on. Submits a GET that re-runs the current
# search with overridden topK / reRankDocs / reRankWeight; the values persist
# across facet/pagination navigation via search_state_fields.
#
# See SearchBehavior::SemanticQuery (which reads the same params) and
# SemanticSearch.tuning_enabled?.
class SemanticTuningComponent < ViewComponent::Base
  Field = Struct.new(:param, :label, :default, :step, :max_value, :help)

  FIELDS = [
    Field.new(:semantic_top_k, 'topK (neighbors)',
              SearchBehavior::SemanticQuery::SEMANTIC_TOP_K, 1,
              SearchBehavior::SemanticQuery::MAX_TOP_K,
              'Nearest-neighbor vectors fetched — the semantic candidate pool (recall).'),
    Field.new(:semantic_rerank_docs, 'reRankDocs',
              SearchBehavior::SemanticQuery::SEMANTIC_RERANK_DOCS, 1,
              SearchBehavior::SemanticQuery::MAX_RERANK_DOCS,
              'How many top results get re-scored by vector similarity.'),
    Field.new(:semantic_rerank_weight, 'reRankWeight',
              SearchBehavior::SemanticQuery::SEMANTIC_RERANK_WEIGHT, 0.5,
              SearchBehavior::SemanticQuery::MAX_RERANK_WEIGHT,
              'Weight of the vector score in the rerank. 0 = keyword-only.'),
    Field.new(:semantic_min_similarity, 'min similarity (floor)',
              SearchBehavior::SemanticQuery::SEMANTIC_MIN_SIMILARITY, 0.01,
              SearchBehavior::SemanticQuery::MAX_MIN_SIMILARITY,
              'Cosine floor: drop vector hits below this (0 = off). The ' \
              'out-of-scope knob; keep below ~0.83 to spare cross-lingual hits.')
  ].freeze

  def initialize(search_state:)
    @search_state = search_state
    super()
  end

  def render?
    SemanticSearch.query_enabled? && SemanticSearch.tuning_enabled?
  end

  def current_value(field)
    @search_state.params[field.param].presence || field.default
  end

  # Preserve the current search (q, search_field, facets, sort, ...) as hidden
  # fields, minus the tuning params (supplied by the visible inputs) and page.
  def preserved_params
    @search_state.params_for_search.except(:page, *FIELDS.map(&:param))
  end
end
