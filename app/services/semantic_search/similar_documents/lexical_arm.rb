# frozen_string_literal: true

module SemanticSearch
  module SimilarDocuments
    # The NON-EMBEDDING arm of "Related collections": collections sharing this
    # one's creator, subject headings or names.
    #
    # It exists because of a measured ceiling, not a hunch. Over 236
    # archivist-authored cases (relationships stated in EAD relatedmaterial), 10%
    # are found by NEITHER embedding model, and the union of two models beats the
    # better one by only +0.030 - so no amount of embedding-model shopping
    # recovers them. Those misses are provenance-shaped: "papers split across two
    # accessions", "his correspondence is filed under SC0064A". A 37-character
    # title cannot express that; a shared creator string states it outright.
    # Different evidence, not better evidence of the same kind.
    module LexicalArm
      # Boosts reflect how strongly a shared value implies relatedness AND how
      # often the field is populated on collection records (measured over 6,192):
      #   creator_ssim          58%  - a shared creator is near-proof
      #   access_subjects_ssim  70%  - shared LCSH: topical, solid
      #   names_ssim           100%  - universal but noisy; "Stanford University"
      #                                is everywhere, so it is weighted lowest and
      #                                leans on Lucene IDF to favour rare names
      FIELDS = { 'creator_ssim' => 4, 'access_subjects_ssim' => 2, 'names_ssim' => 1 }.freeze
      # Cap per field: a collection listing 300 names would otherwise build an
      # enormous disjunction and drown the specific signal in common terms.
      MAX_TERMS_PER_FIELD = 8

      module_function

      # @return [Hash{String=>Hash}] collection id => match info, best first
      def neighbours(source, collection_id, connection:, rows:, fields:)
        clauses = query(source)
        return {} if clauses.blank?

        search(clauses, collection_id, connection: connection, rows: rows, fields: fields)
          .each_with_object({}) do |doc, acc|
            id = doc['id'].to_s
            # The collection itself matched; no component title to explain.
            acc[id] ||= { score: doc['score'], matched_id: id, matched_title: nil }
          end
      end

      # A boosted disjunction over the source's own values. These are string
      # fields, so each clause is an exact term match and Lucene's IDF does the
      # useful work: a shared "Bloch, Felix" counts for far more than a shared
      # "Stanford University".
      def query(source)
        FIELDS.filter_map do |field, boost|
          values = Array(source[field]).reject { |v| v.to_s.strip.empty? }.first(MAX_TERMS_PER_FIELD)
          next if values.empty?

          "(#{values.map { |v| "#{field}:\"#{escape(v)}\"" }.join(' OR ')})^#{boost}"
        end.join(' OR ')
      end

      # fq restricts to collection records and drops the source. Unlike the KNN
      # arm there is no sibling problem to clean up afterwards, because components
      # cannot match at all.
      def search(clauses, collection_id, connection:, rows:, fields:)
        response = connection.post('select',
                                   data: { q: clauses, defType: 'lucene', rows: rows,
                                           fq: ['level_ssim:Collection',
                                                "-id:\"#{collection_id}\""],
                                           fl: fields, wt: 'json' })
        response.dig('response', 'docs') || []
      end

      def escape(value)
        value.to_s.gsub('\\', '\\\\\\\\').gsub('"', '\"')
      end
    end
  end
end
