# frozen_string_literal: true

require_relative '../../../app/services/identifier_service'

module Sul
  ##
  # A Traject utility class to normalize identifiers
  class NormalizedId
    # The Arclight to_field directive sends kwargs (:title and :repository)
    # to this class and we use the id and title to form the collection id
    def initialize(id, **kwargs)
      @id = id
      @title = kwargs[:title]
    end

    attr_reader :id, :title

    def to_s
      IdentifierService.new([id, title]).to_s
    end
  end
end
