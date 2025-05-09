# frozen_string_literal: true

module SearchBehavior
  # This SearchBuilder processor chain method modifies the sort order of the
  # results so that the collection is last when the user has browsed digital content
  # from the collection page. It does not make sense to show the collection first in
  # this case, since that is the page the user was just on.
  module DigitalContentSort
    def apply_digital_content_sort(solr_parameters)
      return unless blank_query? && relevance_sort? && access_and_collection_facets_applied?

      solr_parameters['sort'] = 'if(eq(sort_isi,0),0,div(1,field(sort_isi))) desc'
    end

    private

    def blank_query?
      blacklight_params[:q].blank?
    end

    def access_and_collection_facets_applied?
      blacklight_params[:f]&.fetch('access', [])&.include?('digital_content') &&
        blacklight_params[:f]&.fetch('collection', []).present?
    end

    def relevance_sort?
      blacklight_params[:sort] == 'relevance' || blacklight_params[:sort].blank?
    end
  end
end
