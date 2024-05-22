# frozen_string_literal: true

module Aspace
  class AspaceResourceError < StandardError; end

  # Model for an Aspace resource to manage information
  # needed for downloading and updating resources in ArcLight
  class Resource
    attr_reader :uri, :repository_code, :ead_id, :identifier

    def initialize(uri:, repository_code:, ead_id: nil, identifier: nil)
      @uri = uri
      @repository_code = repository_code
      @ead_id = ead_id
      @identifier = identifier
    end

    def file_name
      file_identifier.sub(/(\.xml)?$/i, '').parameterize
    end

    def arclight_repository_code
      ArclightRepositoryMapper.map_to_code(aspace_repository_code: repository_code, file_identifier:)
    end

    private

    # "identifier" can be entered in ASpace by archivists
    # and often matches the EAD ID, but with variable punctionation or spacing.
    # #
    # If no EAD ID or identifier is provided, throw an error.
    # We need an identifier to generate a file name and determine the repository code
    def file_identifier
      ead_id || identifier || raise(AspaceResourceError,
                                    'Resources from ArchivesSpace must have an EAD ID or identifier')
    end
  end
end
