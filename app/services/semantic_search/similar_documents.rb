# frozen_string_literal: true

module SemanticSearch
  # "Related collections": given a document, find other COLLECTIONS whose
  # embedding is nearest to this one's, using the vectors already in Solr.
  #
  # No embedding API call and no gateway key - `embedding_vector` is stored, so a
  # document's own vector is read back and reused as the KNN query. Documents
  # indexed before that schema change (or with ENABLE_SEMANTIC_INDEXING off) have
  # no vector, and this returns [] rather than failing.
  #
  # Two deliberate design choices, both from measured behaviour:
  #
  #   * We key off the COLLECTION's vector, never a component's. A thin component
  #     ("Leaflets and documents no.1") embeds to a generic container label, so its
  #     nearest neighbours are other generic labels from unrelated repositories
  #     ("Other Documents", "Pamphlets:"). Collection-level vectors carry real
  #     description and produce good suggestions.
  #   * The source's own collection is excluded and results are deduped to one row
  #     per collection. Without that, a collection's own components dominate its
  #     neighbourhood - 111 of a 300-doc pool for ms_3791.
  module SimilarDocuments
    # Fetched before filtering. Siblings are dropped AFTER topK (Solr applies the
    # KNN cut first), so this has to be comfortably larger than the number of
    # suggestions we want.
    POOL = 200
    DEFAULT_LIMIT = 5
    META_FIELDS = 'id,_root_,title_tesim,collection_title_tesim,repository_ssim,level_ssm'

    # Reciprocal rank fusion, WEIGHTED. Rank-based because a cosine and a Lucene
    # score cannot be summed meaningfully.
    #
    # The weight is not decoration. Equal weighting (1.0) was measured on 238
    # archivist-authored cases and made the panel WORSE where it matters:
    # recall@5 -0.065, any@5 -0.063, losing 32 cases at top-5 to rescue 17. The
    # arms are not co-equal - the vector arm is simply more precise, and giving
    # the lexical arm an equal vote lets shared-subject noise displace good hits.
    # It earns its place as a MINORITY vote that can still surface a collection
    # the vector arm never saw.
    #
    # 0.15 is measured, not guessed - a sweep over the same 238 cases
    # (scratchpad/eval_lexical_arm.rb): every metric improves and all four
    # intervals exclude zero, and it degrades monotonically as the weight rises.
    #   w=0.15  recall@5 +0.039 [+0.015,+0.065]   any@5 +0.038 [+0.008,+0.067]
    #   w=0.30  recall@5 +0.013                   any@5 +0.013
    #   w=0.50  recall@5 -0.014                   any@5 -0.013
    #   w=1.00  recall@5 -0.065                   any@5 -0.063
    RRF_K = 60
    DEFAULT_LEXICAL_WEIGHT = 0.15
    # What we fetch for the SOURCE collection: its vector plus the lexical fields.
    SOURCE_FIELDS = "id,embedding_vector,#{LexicalArm::FIELDS.keys.join(',')}".freeze

    module_function

    # @param document [SolrDocument] the document whose page we are on
    # @param limit [Integer] how many suggestions to return
    # @return [Array<SolrDocument>] nearest OTHER collections, best first
    def for(document, limit: DEFAULT_LIMIT)
      collection_id = collection_of(document)
      return [] if collection_id.blank?

      source = source_for(collection_id)
      return [] if Array(source['embedding_vector']).blank?

      neighbours(source, collection_id, limit)
    rescue StandardError => e
      # A suggestion panel must never take down a record page.
      Rails.logger.warn("[SemanticSearch] similar documents failed for #{document&.id}: #{e.class}: #{e.message}")
      []
    end

    def collection_of(document)
      return nil if document.nil?

      collection_key(document) || document.id.to_s.split('_aspace_').first.presence
    end

    # Solr returns `_root_` as a bare string here, but Blacklight documents can
    # hand back an array; normalise both. Falls back to the id with any
    # `_aspace_` component suffix stripped, which is how ArcLight component ids
    # map to their collection.
    def collection_key(doc)
      root = doc.respond_to?(:[]) ? doc['_root_'] : nil
      Array(root).first.presence
    end

    # The source collection record: its stored vector, plus the fields the lexical
    # arm matches on. One request rather than two - the lexical fields are cheap
    # next to a 768-float vector we are already transferring.
    def source_for(collection_id)
      response = connection.get('select', params: { q: "id:\"#{collection_id}\"", defType: 'lucene',
                                                    rows: 1, fl: SOURCE_FIELDS })
      response.dig('response', 'docs')&.first || {}
    end

    # KNN against the same field the search path queries.
    #
    # POST, not GET: a 768-dim literal is ~8.4KB and Solr answers a GET with 414.
    # defType=lucene is REQUIRED: the /select handler defaults to edismax, which
    # tokenises the floats into ~768 boolean clauses and fails with
    # "too many nested clauses; maxClauseCount is set to 1024" at any topK.
    def neighbours(source, collection_id, limit)
      vector_hits = best_per_collection(knn(source['embedding_vector']), collection_id)
      return resolve_collections(vector_hits.keys.first(limit), vector_hits) unless lexical?

      lexical_hits = LexicalArm.neighbours(source, collection_id, connection: connection,
                                                                  rows: POOL,
                                                                  fields: "#{META_FIELDS},score")
      ranked = fuse(vector_hits.keys, lexical_hits.keys)
      resolve_collections(ranked.first(limit), merge_matches(vector_hits, lexical_hits))
    end

    def lexical?
      SemanticSearch.related_lexical_enabled?
    end

    # Appearing in BOTH arms is itself strong evidence, which summing reciprocal
    # ranks rewards automatically. A weight of 0 reproduces the vector-only order
    # exactly (lexical-only ids sort to the bottom) - a control worth keeping,
    # since it is how a silently-ignored tuning param would show itself.
    def fuse(vector_ids, lexical_ids)
      scores = Hash.new(0.0)
      accumulate(scores, vector_ids, 1.0)
      accumulate(scores, lexical_ids, lexical_weight)
      scores.sort_by { |id, score| [-score, id] }.map(&:first)
    end

    def accumulate(scores, ids, weight)
      ids.each_with_index { |id, index| scores[id] += weight / (RRF_K + index + 1) }
    end

    def lexical_weight
      Float(ENV.fetch('SEMANTIC_RELATED_LEXICAL_WEIGHT', DEFAULT_LEXICAL_WEIGHT))
    end

    # Vector match info wins where both arms found a collection: it may carry the
    # component title that explains the connection, which the lexical arm never has.
    def merge_matches(vector_hits, lexical_hits)
      lexical_hits.merge(vector_hits)
    end

    def knn(vector)
      literal = "[#{SemanticSearch.solr_vector(vector).join(',')}]"
      response = connection.post('select',
                                 data: { q: "{!knn f=embedding_vector topK=#{POOL}}#{literal}",
                                         defType: 'lucene', rows: POOL,
                                         fl: "#{META_FIELDS},score", wt: 'json' })
      response.dig('response', 'docs') || []
    end

    # Best-scoring hit per collection, remembering WHICH document matched: often
    # it is a component, and its title is the whole reason the suggestion is
    # interesting ("Applied Electronics Laboratory: Sit-in" for a collection
    # blandly titled "School of Engineering, Dean's Office records").
    def best_per_collection(docs, collection_id)
      docs.reject { |doc| own_collection?(doc, collection_id) }
          .each_with_object({}) do |doc, acc|
            key = collection_key(doc) || doc['id'].to_s
            acc[key] ||= { score: doc['score'], matched_id: doc['id'].to_s, matched_title: title_of(doc) }
          end
    end

    # A KNN hit is often a COMPONENT of another collection, so its own title
    # describes an item rather than the collection we link to. Fetch the
    # collection-level records so title and link agree, but carry the matched
    # document through as `matched_title` so the UI can explain the connection.
    def resolve_collections(ids, matches)
      return [] if ids.empty?

      by_id = fetch_by_id(ids)
      ids.filter_map { |id| by_id[id] && decorate(by_id[id], matches[id]) }
    end

    def fetch_by_id(ids)
      response = connection.get('select', params: { q: '*:*', fq: "{!terms f=id}#{ids.join(',')}",
                                                    rows: ids.size, fl: META_FIELDS })
      (response.dig('response', 'docs') || []).index_by { |doc| doc['id'].to_s }
    end

    # `matched_title` is nil when the collection itself was the nearest hit -
    # there is no extra context to explain in that case.
    def decorate(doc, match)
      component_won = match[:matched_id] != doc['id'].to_s
      SolrDocument.new(doc.merge('score' => match[:score],
                                 'matched_title' => component_won ? match[:matched_title] : nil,
                                 'matched_id' => component_won ? match[:matched_id] : nil))
    end

    def title_of(doc)
      Array(doc['title_tesim']).first.presence || Array(doc['collection_title_tesim']).first.presence
    end

    # True for the source collection itself and for any of its components.
    def own_collection?(doc, collection_id)
      (collection_key(doc) || doc['id'].to_s) == collection_id || doc['id'].to_s == collection_id
    end

    def connection
      Blacklight.default_index.connection
    end
  end
end
