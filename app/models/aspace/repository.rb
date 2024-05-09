# frozen_string_literal: true

module Aspace
  # Models an Aspace repository
  class Repository
    attr_reader :uri, :code

    def initialize(repo_code:, uri:)
      @code = repo_code.downcase
      @uri = uri
    end

    def id
      @id ||= uri.split('/').last
    end

    def harvestable?
      @harvestable ||= Settings.aspace.harvestable_repository_codes.include?(code)
    end
  end
end
