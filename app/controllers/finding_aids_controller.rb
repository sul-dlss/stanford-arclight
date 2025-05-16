# frozen_string_literal: true

# This controller handles the resolution of ARK IDs to finding aids in the solr index
class FindingAidsController < ApplicationController
  def resolve
    @ark_id = params[:ark_id]

    response = search_solr

    if response['response']['numFound'].positive?
      solr_id = response['response']['docs'][0]['id']
      redirect_to solr_document_path(solr_id)
    else
      render plain: 'Finding aid not found', status: :not_found
    end
  end

  def search_solr
    repository.search(
      rows: 1,
      fl: 'id',
      fq: %(sul_ark_id_ssi:"#{@ark_id}"),
      q: '*:*',
      sort: 'id ASC',
      facet: false
    )
  end

  delegate :repository, to: :blacklight_config

  def blacklight_config
    @blacklight_config ||= CatalogController.blacklight_config.configure
  end
end
