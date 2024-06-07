# frozen_string_literal: true

require 'arclight/exceptions'

module Sul
  ##
  # A utility class to normalize identifiers
  class NormalizedId
    # The Arclight to_field directive sends kwargs (:title and :repository)
    # to this class and we use the id and title to form the collection id
    def initialize(id, **kwargs)
      @id = id
      @title = kwargs[:title]
    end

    def to_s
      normalize
    end

    private

    attr_reader :id, :title

    def normalize
      # De-duplicate edge cases where id has been generated from title due to missing EAD ID
      # E.g. don't return Université de Toulouse_universite-de-toulouse
      # Instead, return only universite-de-toulouse.
      # Otherwise return something like ars0009_belva-kibler-and-donald-morgan
      normalized_id = [id, title].compact.reject(&:empty?).map do |string|
        string.split.map(&:parameterize).reject(&:empty?).take(5).join('-')
      end.compact_blank.uniq.join('_')

      raise Arclight::Exceptions::IDNotFound if normalized_id.blank?

      normalized_id
    end
  end
end
