# frozen_string_literal: true

module SemanticSearch
  # Builds the text that gets embedded for a single Solr document.
  #
  # It reuses fields the Arclight/Traject indexer has *already* extracted into
  # the Traject `output_hash` (so we don't re-derive any parsing/inheritance
  # logic). Two groups are formatted differently:
  #
  #   * Prose fields (title, scope/content, bio/hist, abstract): concatenated
  #     as-is.
  #   * Controlled-access terms (subjects, names, places): appended after the
  #     prose as a labeled, capped list, e.g.
  #       "Subjects: X; Y; Z. Names: A; B. Places: C."
  #
  # Controlled-access terms are included on purpose: for minimally-processed
  # collections with thin prose they're often the only meaningful semantic
  # signal, and they bridge vocabulary gaps between researcher phrasing and
  # archival terminology. Each category is capped so a heavily-tagged document
  # can't drown out its own prose in the embedding.
  #
  # For the rare doc that exceeds the embed-text budget, only the prose is
  # trimmed (from its tail - bioghist, then scope - keeping the title), so the
  # short, high-signal controlled-access terms always survive.
  #
  # This class is Rails-free so it can run inside the standalone Traject process.
  class TextBuilder
    # Solr fields holding prose, in the order we concatenate them. We use
    # normalized_title_ssm (not title_tesim) for the title: the two are the same
    # title differing only by an appended date, and normalized_title_ssm is built
    # from title_tesim - so including both just duplicated the title in the embed
    # text (badly for collections whose "title" is a paragraph).
    PROSE_FIELDS = %w[
      normalized_title_ssm
      abstract_tesim
      scopecontent_tesim
      bioghist_tesim
    ].freeze

    # Controlled-access categories: label => Solr field holding the terms.
    ACCESS_FIELDS = {
      'Subjects' => 'access_subjects_ssim',
      'Names' => 'names_ssim',
      'Places' => 'places_ssim'
    }.freeze

    # Cap per controlled-access category. Start conservative (10-15 range from
    # the spec); revisit during stage relevance review.
    TERMS_PER_CATEGORY = 12

    # Character budget for the whole embed text (~7.5k tokens, under the model's
    # 8,192 limit). Only the handful of very long docs ever hit it.
    MAX_EMBED_CHARS = 30_000

    # @param output_hash [Hash] the Traject context output_hash for one doc
    def initialize(output_hash)
      @output_hash = output_hash || {}
    end

    # @return [String, nil] the text to embed, or nil when there is nothing
    #   meaningful to embed (so the caller can skip the doc entirely).
    def call
      # NOTE: avoid ActiveSupport's blank? here - this class runs in the
      # Rails-free Traject process. prose/controlled_access always return a
      # String (possibly empty), never nil.
      access = controlled_access
      # Field-aware truncation: trim only the prose (its tail is bioghist, then
      # scope - the least-central content; the title stays) so the high-signal
      # controlled-access terms always survive the budget. Docs under budget are
      # unchanged.
      parts = [fit_prose(prose, access), access].reject(&:empty?)
      return nil if parts.empty?

      parts.join("\n\n")
    end

    private

    attr_reader :output_hash

    def fit_prose(prose_text, access_text)
      reserved = access_text.empty? ? 0 : access_text.length + 2 # "\n\n" separator
      budget = [MAX_EMBED_CHARS - reserved, 0].max
      prose_text.length > budget ? prose_text[0, budget] : prose_text
    end

    def prose
      PROSE_FIELDS
        .flat_map { |field| Array(output_hash[field]) }
        .map { |value| value.to_s.strip }
        .reject(&:empty?)
        .uniq
        .join("\n")
    end

    def controlled_access
      ACCESS_FIELDS.filter_map do |label, field|
        terms = access_terms(field)
        next if terms.empty?

        "#{label}: #{terms.join('; ')}."
      end.join(' ')
    end

    def access_terms(field)
      Array(output_hash[field])
        .map { |value| value.to_s.strip }
        # Arclight's `//corpname` sweep pulls the <repository> corpname into
        # names_ssim; it's the administrative repository designation (constant per
        # collection), not a meaningful name - drop it.
        .reject { |value| value.empty? || repository_names.include?(value) }
        .uniq
        .first(TERMS_PER_CATEGORY)
    end

    def repository_names
      @repository_names ||= Array(output_hash['repository_ssim']).map { |value| value.to_s.strip }.reject(&:empty?)
    end
  end
end
