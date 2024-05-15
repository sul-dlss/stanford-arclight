# frozen_string_literal: true

module Aspace
  # Model for an Aspace repository to manage information
  # needed for downloading and updating a repository's resources
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

    def each_published_resource(updated_after: nil)
      return enum_for(:each_published_resource, updated_after:) unless block_given?

      client.published_resource_uris(repository_id: id, updated_after:).each do |resource|
        yield Aspace::Resource.new(**resource.symbolize_keys.merge({ repository_code: code }))
      end
    end

    def each_published_resource_with_updated_components(updated_after:, uris_to_exclude: nil)
      unless block_given?
        return enum_for(:each_published_resource_with_updated_components, updated_after:, uris_to_exclude:)
      end

      client.published_resource_with_updated_component_uris(repository_id: id, updated_after:,
                                                            uris_to_exclude:).each do |resource|
        yield Aspace::Resource.new(**resource.symbolize_keys.merge({ repository_code: code }))
      end
    end

    def each_published_resource_with_updated_agents(updated_after:, uris_to_exclude: nil)
      unless block_given?
        return enum_for(:each_published_resource_with_updated_agents, updated_after:, uris_to_exclude:)
      end

      client.published_resource_with_linked_agent_uris(repository_id: id, updated_after:,
                                                       uris_to_exclude:).each do |resource|
        yield Aspace::Resource.new(**resource.symbolize_keys.merge({ repository_code: code }))
      end
    end

    private

    def client
      @client ||= AspaceClient.new
    end
  end
end
