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
      # If the id is nil or empty, we use the title to form the id
      # If the id is a string with a file extension, we remove the file extension
      normalized_id = [id, title].compact.reject(&:empty?).map do |string|
        string.sub(/(\.xml)?$/i, '').split.map(&:parameterize).reject(&:empty?).take(5).join('-')
      end.compact_blank.uniq.first

      raise Arclight::Exceptions::IDNotFound if normalized_id.blank?

      normalized_id
    end
  end
end
