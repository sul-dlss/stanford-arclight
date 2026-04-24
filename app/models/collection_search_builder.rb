# frozen_string_literal: true

class CollectionSearchBuilder < SearchBuilder
  self.default_processor_chain += [:wrap_with_block_join]

  # Wraps the user query in a Solr block join parent query so that only
  # collection-level documents are returned, scored by their best-matching
  # child component. Skips when no query is present (q.alt handles that case)
  # or when the request is routed to the plain edismax handler (e.g. within_collection).
  def wrap_with_block_join(solr_parameters)
    return unless solr_parameters[:qt] == 'collection_search'

    user_query = solr_parameters[:q]
    if user_query.blank?
      # q.alt is edismax-only; the lucene parser ignores it, so set *:* explicitly
      solr_parameters[:q] = '*:*'
      # Skip the collection filter when loading within a specific finding aid (ArcLight
      # hierarchy requests constrain via _root_, and we must not exclude their components)
      existing_fqs = Array(solr_parameters[:fq]).map(&:to_s)
      within_collection = existing_fqs.any? { |fq| fq.include?('_root_') || fq.include?('_nest_parent_') }
      solr_parameters[:fq] = existing_fqs + ['level_ssim:Collection'] unless within_collection
      return
    end

    escaped_query = user_query.gsub('\\', '\\\\\\\\').gsub('"', '\\"')
    solr_parameters[:q] = '{!parent which=\'level_ssim:Collection\' score=max}' \
                          "(-level_ssim:Collection AND _query_:\"{!edismax qf=$qf pf=$pf mm=$mm ps=$ps tie=$tie}#{escaped_query}\")"
    solr_parameters[:fq] = Array(solr_parameters[:fq]) + ['level_ssim:Collection']
  end
end
