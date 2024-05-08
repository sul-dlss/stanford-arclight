# frozen_string_literal: true

require 'arclight/exceptions'

module Sul
  ##
  # A utility class to normalize identifiers
  class NormalizedId
    # The ead_config.rb id to_field directive sends kwargs (:title and :repository)
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
      normalized_id = [id.strip.tr('.', '-'), title&.truncate_words(5, omission: '')&.parameterize].compact.join('_')

      raise Arclight::Exceptions::IDNotFound if normalized_id.blank?

      normalized_id
    end
  end
end
