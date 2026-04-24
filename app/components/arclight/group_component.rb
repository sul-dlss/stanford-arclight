# frozen_string_literal: true

module Arclight
  class GroupComponent < Blacklight::Document::GroupComponent
    def compact?
      helpers.document_index_view_type.to_s == 'compact'
    end

    def document
      @document ||= @group.docs.first.collection
    end

    def presenter
      @presenter ||= Arclight::ShowPresenter.new(document, helpers).with_field_group('group_header_field')
    end

    def collection_show_url
      helpers.search_state.url_for_document(document)
    end

    def search_within_collection_url
      search_catalog_path(
        helpers.search_without_group.deep_merge(
          search_field: 'within_collection',
          f: { collection: [document.collection_name] }
        )
      )
    end

    # The collection document if it appears as one of the group's result docs, nil otherwise.
    # Identified by matching the doc id against the group key (the _root_ field value).
    def collection_doc_in_results
      @collection_doc_in_results ||= @group.docs.find { |doc| doc['id'] == @group.key }
    end

    # The result docs to render as cards, excluding the collection document when present.
    def component_docs
      return @group.docs unless collection_doc_in_results

      @component_docs ||= @group.docs.reject { |doc| doc['id'] == @group.key }
    end

    # Total count of component (non-collection) results, adjusted when the collection doc matched.
    def component_count
      collection_doc_in_results ? @group.total - 1 : @group.total
    end

    # True when there are more component results than the cards we are currently displaying.
    def more_component_results?
      component_count > component_docs.size
    end
  end
end
