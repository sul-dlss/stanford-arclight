# frozen_string_literal: true

module SemanticSearch
  # "Related collections": given a document, find other COLLECTIONS whose
  # embedding is nearest to this one's, using the vectors already in Solr.
  #
  # No embedding API call and no gateway key - `embedding_vector` is stored, so a
  # document's own vector is read back and reused as the KNN query. Documents
  # indexed before that schema change (or with no API key at index time) have no
  # vector, and this returns [] rather than failing.
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
    SOURCE_FIELDS = 'id,embedding_vector'

    module_function

    # @param document [SolrDocument] the document whose page we are on
    # @param limit [Integer] how many suggestions to return
    # @return [Array<SolrDocument>] nearest OTHER collections, best first
    def for(document, limit: DEFAULT_LIMIT)
      collection_id = collection_of(document)
      return [] if collection_id.blank?

      source = source_for(collection_id)
      vector = source['embedding_vector']
      return [] if Array(vector).blank?

      neighbours(vector, collection_id, limit)
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

    # The source collection record: just its stored vector.
    def source_for(collection_id)
      response = connection.get('select', params: { q: "id:\"#{collection_id}\"", defType: 'lucene',
                                                    rows: 1, fl: SOURCE_FIELDS })
      response.dig('response', 'docs')&.first || {}
    end

    def neighbours(vector, collection_id, limit)
      hits = best_per_collection(knn(vector), collection_id)
      resolve_collections(hits.keys.first(limit), hits)
    end

    # KNN against the same field the search path queries.
    #
    # POST, not GET: a 768-dim literal is ~8.4KB and Solr answers a GET with 414.
    # defType=lucene is REQUIRED: the /select handler defaults to edismax, which
    # tokenises the floats into ~768 boolean clauses and fails with
    # "too many nested clauses; maxClauseCount is set to 1024" at any topK.
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
