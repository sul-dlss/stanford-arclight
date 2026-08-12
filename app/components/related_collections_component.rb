# frozen_string_literal: true

# Sidebar panel on record pages listing collections whose embeddings are nearest
# to the current record's collection - vector-based "more like this" discovery,
# surfacing related material that shares no keywords.
#
# Renders only when SemanticSearch.related_enabled? AND there is something to
# show, so a record with no stored vector (indexed before the stored="true"
# schema change, or with semantic indexing off) simply shows no panel.
#
# See SemanticSearch::SimilarDocuments for why suggestions are keyed off the
# COLLECTION vector rather than the current component's.
class RelatedCollectionsComponent < ViewComponent::Base
  LIMIT = 5

  def initialize(document:, limit: LIMIT)
    @document = document
    @limit = limit
    super()
  end

  def render?
    SemanticSearch.related_enabled? && related.any?
  end

  def related
    @related ||= SemanticSearch::SimilarDocuments.for(@document, limit: @limit)
  end

  # Collection title, falling back through the fields ArcLight actually populates.
  def title_for(doc)
    Array(doc['collection_title_tesim']).first.presence ||
      Array(doc['title_tesim']).first.presence ||
      doc.id
  end

  def repository_for(doc)
    Array(doc['repository_ssim']).first
  end

  # When the nearest match was a COMPONENT of the suggested collection, its title
  # is usually the reason the suggestion is interesting - a collection titled
  # "School of Engineering, Dean's Office records" surfaces because it contains
  # "Applied Electronics Laboratory: Sit-in". Showing it explains the connection,
  # which matters when the link is not lexically obvious.
  def matched_title_for(doc)
    doc['matched_title'].presence
  end

  # Linked, not just displayed. These labels are often terse ("Shockley, W.",
  # "1. Tapes") because archival folder labels are terse - but the destination is
  # precisely the folder a researcher would request, and ArcLight component pages
  # carry breadcrumbs and collection context, so it is never a dead end.
  def matched_path_for(doc)
    id = doc['matched_id'].presence or return nil
    helpers.solr_document_path(id)
  end

  # Link to the collection, not the matched component: the panel is about
  # collections, and a matched component's own page is rarely the useful landing
  # spot for someone browsing sideways.
  def path_for(doc)
    helpers.solr_document_path(Array(doc['_root_']).first.presence || doc.id)
  end

  # Shown only where the tuning flag is on (dev/stage), for relevance debugging.
  def score_for(doc)
    return nil unless SemanticSearch.tuning_enabled?

    format('%.3f', doc['score']) if doc['score']
  end
end
