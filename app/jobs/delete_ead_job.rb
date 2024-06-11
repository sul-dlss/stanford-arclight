# frozen_string_literal: true

##
# Background job that deletes an indexed collection from Solr
# if we find it is no longer published or no longer exists in ASpace
class DeleteEadJob < ApplicationJob
  def self.enqueue_all
    AspaceRepositories.all_harvestable.each do |repository|
      perform_later(repository_id: repository.id)
    end
  end

  # @param repository_id [String] the ASpace repository id, such as '11'
  def perform(repository_id:)
    indexed_eads = IndexedEads.new(repository_id:).all
    published_eads = AspaceClient.new.all_published_resource_uris_by(repository_id:)

    eads_to_delete = indexed_eads.keys - published_eads
    ids_to_delete = indexed_eads.slice(*eads_to_delete).values

    return if ids_to_delete.none?

    Blacklight.default_index.connection.delete_by_id(ids_to_delete)
    Blacklight.default_index.connection.commit
  end

  # Fetches all the indexed EAD files for an aspace repository
  class IndexedEads
    attr_reader :repository_id

    PAGE_SIZE = 250

    def initialize(repository_id:)
      @repository_id = repository_id
    end

    # returns a hash where each key is an aspace resource uri and each value is a Solr document id
    # e.g. {'/repositories/1/resources/123' => 'sc0908-xml', '/repositories/1/resources/456'' => 'm0001-xml'}
    def all
      each.to_h
    end

    private

    # rubocop:disable Metrics/MethodLength
    def each(&)
      return enum_for(:each) unless block_given?

      this_page = 0
      last_page = nil

      while last_page.nil? || this_page < last_page
        response = repository.search(
          rows: PAGE_SIZE,
          start: this_page,
          fl: 'id,resource_uri_ssi',
          fq: "repository_uri_ssi:\"/repositories/#{repository_id}\"",
          sort: 'id ASC'
        )

        this_page += PAGE_SIZE
        last_page = response.dig('response', 'numFound')

        response.dig('response', 'docs').map { |result| [result['resource_uri_ssi'], result['id']] }.each(&)
      end
    end
    # rubocop:enable Metrics/MethodLength

    delegate :repository, to: :blacklight_config

    def blacklight_config
      @blacklight_config ||= CatalogController.blacklight_config.configure
    end
  end
end
