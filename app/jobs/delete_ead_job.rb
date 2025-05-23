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
  # @param skip_delete_safeguard [Boolean] if true, skips the safeguard that prevents excessive deletes
  def perform(repository_id:, aspace_config_set:, ark_shoulder:, skip_delete_safeguard: false)
    indexed_eads = indexed_eads(ark_shoulder:)
    published_eads = AspaceClient.new(aspace_config_set:).all_published_resource_arks_by(repository_id:)

    eads_to_delete = indexed_eads.keys - published_eads
    ids_to_delete = indexed_eads.slice(*eads_to_delete).values

    return if ids_to_delete.none?

    unless skip_delete_safeguard
      DeleteSafeguard.check(delete_count: ids_to_delete.count,
                            index_count: indexed_eads.count)
    end

    delete_and_commit_to_solr(ids_to_delete)
  end

  def delete_and_commit_to_solr(ids_to_delete)
    Blacklight.default_index.connection.delete_by_id(ids_to_delete)
    Blacklight.default_index.connection.commit
  end

  def indexed_eads(ark_shoulder:)
    SolrPaginatedQuery.new(filter_queries: { sul_ark_shoulder_ssi: ark_shoulder },
                           fields_to_return: %w[sul_ark_id_ssi id]).all.to_h
  end
end
