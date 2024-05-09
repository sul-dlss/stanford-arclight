# frozen_string_literal: true

module Aspace
  # Model for an Aspace resource to manage information
  # needed for downloading and updating resources in ArcLight
  class Resource
    attr_reader :ead_id, :uri, :repository_code

    def initialize(ead_id:, uri:, repository_code:)
      @ead_id = ead_id
      @uri = uri
      @repository_code = repository_code
    end

    def file_name
      ead_id.sub(/(\.xml)?$/i, '').parameterize
    end

    def arclight_repository_code
      ArclightRepositoryMapper.map_to_code(aspace_repository_code: repository_code, ead_id:)
    end
  end
end
