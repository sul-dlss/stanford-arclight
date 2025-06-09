# frozen_string_literal: true

require_relative '../../../app/services/identifier_service'

module Sul
  ##
  # A Traject utility class to normalize identifiers
  class NormalizedId
    # The Arclight to_field directive sends kwargs (:unitid, :title and :repository)
    # to this class and we use the id (EAD ID), unitid, or title to form the collection id
    def initialize(id, **kwargs)
      @id = id # this is the EAD ID
      @unitid = kwargs[:unitid]
      @title = kwargs[:title]
    end

    attr_reader :id, :unitid, :title

    def to_s
      IdentifierService.new([id, unitid, title]).to_s
    end
  end
end
