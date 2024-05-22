# frozen_string_literal: true

module Aspace
  # Model for an Aspace resource to manage information
  # needed for downloading and updating resources in ArcLight
  class Resource
    attr_reader :ead_id, :identifier, :uri, :repository_code

    def initialize(ead_id:, identifier:, uri:, repository_code:)
      @ead_id = ead_id
      @identifier = identifier
      @uri = uri
      @repository_code = repository_code
    end

    def file_name
      ead_id_or_fallback_identifier.sub(/(\.xml)?$/i, '').parameterize
    end

    def arclight_repository_code
      ArclightRepositoryMapper.map_to_code(aspace_repository_code: repository_code, ead_id: ead_id_or_fallback_identifier)
    end

    private

    def ead_id_or_fallback_identifier
      ead_id || identifier
    end
  end
end
