# frozen_string_literal: true

module SemanticSearch
  # In-memory nearest-neighbor lookup against the REAL access_subjects_ssim
  # values already in the index - "related topics" suggestions that can never
  # be a term absent from the archive, because the candidate set IS the index
  # (never LLM-generated).
  #
  # Vectors are precomputed offline (scratchpad/extract_subject_vocabulary.rb
  # + scratchpad/embed_subject_vocabulary.rb) and Marshal-loaded once at boot
  # (config/initializers/subject_vocabulary.rb). 6,432 terms x 768 floats is a
  # few MB - small enough to brute-force cosine-compare per request with no
  # dedicated vector store.
  module SubjectVocabulary
    def self.vectors
      @vectors
    end

    def self.vectors=(value)
      @vectors = value
    end

    def self.loaded?
      vectors.present?
    end

    # @param query [String]
    # @param limit [Integer]
    # @return [Array<String>] nearest subject terms, highest similarity first
    def self.related_terms(query, limit: 5)
      return [] unless loaded? && query.present?

      query_vector = EmbeddingService.new.embed(query, task_type: EmbeddingService::QUERY_TASK_TYPE)
      vectors.max_by(limit) { |_term, vector| dot(query_vector, vector) }.map(&:first)
    rescue EmbeddingService::Error => e
      Rails.logger.warn("[SemanticSearch] subject vocabulary lookup failed: #{e.class}: #{e.message}")
      []
    end

    # Vectors are already unit-normalized (EmbeddingService#to_dimensions), so
    # cosine similarity is a plain dot product.
    def self.dot(vector_a, vector_b)
      vector_a.zip(vector_b).sum { |x, y| x * y }
    end

    private_class_method :dot
  end
end
