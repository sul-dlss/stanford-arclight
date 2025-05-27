# frozen_string_literal: true

##
# Background job that deletes an indexed collection from Solr
# if we find it is no longer published or no longer exists in ASpace
class DeleteEadJob < ApplicationJob
  class DeleteEadJobError < StandardError; end

  def self.enqueue_all
    AspaceRepositories.all_harvestable.each do |repository|
      perform_later(repository_id: repository.id,
                    aspace_config_set: repository.aspace_config_set,
                    ark_shoulder: repository.ark_shoulder)
    end
  end

  # @param repository_id [String] the ASpace repository id, such as '11'
  # @param aspace_config_set [String] the ASpace instance configuration set, such as 'default'
  # @param override_excessive_deletes_guard [Boolean] if true, the job will not raise an error if the number of records
  #        to delete exceeds Settings.max_automated_deletes
  def perform(repository_id:, aspace_config_set:, ark_shoulder:, override_excessive_deletes_guard: false)
    indexed_eads = IndexedEads.new(ark_shoulder:).all
    published_eads = AspaceClient.new(aspace_config_set:).all_published_resource_arks_by(repository_id:)

    eads_to_delete = indexed_eads.keys - published_eads
    ids_to_delete = indexed_eads.slice(*eads_to_delete).values

    return if ids_to_delete.none?

    excessive_deletes_guard(ids_to_delete:, override_excessive_deletes_guard:)

    Blacklight.default_index.connection.delete_by_id(ids_to_delete)
    Blacklight.default_index.connection.commit
  end

  # This is a safeguard to prevent deleting too many records at once (indicating something could be wrong).
  # If the number of records to delete exceeds Settings.max_automated_deletes, raise an error instead of proceeding.
  def excessive_deletes_guard(ids_to_delete:, override_excessive_deletes_guard: false)
    return if override_excessive_deletes_guard

    return unless ids_to_delete.size > Settings.max_automated_deletes

    raise DeleteEadJobError, "Attempting to delete #{ids_to_delete.size} records. " \
                             "This exceeds the limit of #{Settings.max_automated_deletes}."
  end

  # Fetches all the indexed EAD files for an aspace repository
  class IndexedEads
    attr_reader :ark_shoulder

    PAGE_SIZE = 250

    def initialize(ark_shoulder:)
      @ark_shoulder = ark_shoulder
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
          fl: 'id,sul_ark_id_ssi',
          fq: ["sul_ark_shoulder_ssi:\"#{ark_shoulder}\""],
          sort: 'id ASC',
          facet: false
        )

        this_page += PAGE_SIZE
        last_page = response.dig('response', 'numFound')

        response.dig('response', 'docs').map { |result| [result['sul_ark_id_ssi'], result['id']] }.each(&)
      end
    end
    # rubocop:enable Metrics/MethodLength

    delegate :repository, to: :blacklight_config

    def blacklight_config
      @blacklight_config ||= CatalogController.blacklight_config.configure
    end
  end
end
