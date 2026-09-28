# frozen_string_literal: true

class SearchBuilder < Blacklight::SearchBuilder
  include Blacklight::Solr::SearchBuilderBehavior
  include BlacklightRangeLimit::RangeLimitBuilder
  include Arclight::SearchBehavior
  include SearchBehavior::DigitalContentSort

  self.default_processor_chain += [:apply_group_sort_parameter,
                                   :apply_digital_content_sort,
                                   :min_match_for_boolean]

  # Upstream Arclight::SearchBehavior#add_hierarchy_behavior sets `fl=*` for
  # hierarchy queries, which drops the inherited `collection:[subquery]`
  # parent lookup that otherwise ran once per child. We narrow `fl` further to
  # only the fields the hierarchy tree view renders.
  HIERARCHY_FL = %w[
    id
    normalized_title_ssm
    level_ssm
    child_component_count_isi
    _nest_path_
    component_level_isim
    containers_ssim
    has_online_content_ssim
  ].join(',').freeze

  def add_hierarchy_behavior(solr_parameters)
    super # upstream sets fl=* here, dropping the collection:[subquery] parent lookup
    return unless search_state.controller&.action_name == 'hierarchy'

    solr_parameters[:fl] = HIERARCHY_FL
  end

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

  # Sets `mm` (minimum should match) to 1 based on presence of boolean operators, overriding default set in Solr.
  # The default value in the request handler (`4<90%`) allows for some non-matching clauses in
  # full-text queries, but leads to unexpected behavior when a user expects to use boolean operators for
  # more advanced search queries. Setting `mm=1` means only 1 clause needs to match, but the lucene query parser (in
  # edismax) will precompose the query strings so everything works out.
  def min_match_for_boolean(solr_parameters)
    return unless search_state.query_param.respond_to?(:match?) &&
                  search_state.query_param&.match?(/\s(AND|OR|NOT)\s/)

    solr_parameters[:mm] = '1'
  end
end
