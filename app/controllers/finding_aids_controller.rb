# frozen_string_literal: true

# This controller handles the resolution of ARK IDs to finding aids in the solr index
class FindingAidsController < ApplicationController
  def resolve
    ark_id = params[:ark_id]
    response = search_solr(ark_id)

    unless response['response']['numFound'].positive?
      raise ActiveRecord::RecordNotFound, "Finding aid not found for ARK ID: #{ark_id}"
    end

    solr_id = response['response']['docs'][0]['id']
    redirect_to solr_document_path(solr_id)
  end

  private

  delegate :repository, to: :blacklight_config

  def search_solr(ark_id)
    ark = ArkNormalizer.normalize(ark_id)
    repository.search(
      rows: 1,
      fl: 'id',
      fq: %(sul_ark_id_ssi:"#{ark}"),
      q: '*:*',
      sort: 'id ASC',
      facet: false
    )
  end

  def blacklight_config
    @blacklight_config ||= CatalogController.blacklight_config.configure
  end
end
