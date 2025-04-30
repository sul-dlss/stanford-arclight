# frozen_string_literal: true

class SearchBuilder < Blacklight::SearchBuilder
  include Blacklight::Solr::SearchBuilderBehavior
  include BlacklightRangeLimit::RangeLimitBuilder
  include Arclight::SearchBehavior

  self.default_processor_chain += [:apply_group_sort_parameter]

  # If no query is supplied when results are grouped and sorted by relevance,
  # we adjust the sort order so that each group is sorted in component order
  # with collections last.
  def apply_group_sort_parameter(solr_parameters)
    return unless blacklight_params[:group] == 'true' && blacklight_params[:q].blank? &&
                  (blacklight_params[:sort] == 'relevance' || blacklight_params[:sort].blank?)

    # sort_isi contains the component order starting with the collection at 0. To put
    # the collection last but leave the remaining components in order we divide 1 by
    # sort_isi values other than 0 and change the sort to DESC.
    solr_parameters['group.sort'] = 'if(eq(sort_isi,0),0,div(1,field(sort_isi))) desc'
  end
end
