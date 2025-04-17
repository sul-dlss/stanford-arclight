# frozen_string_literal: true

module Arclight
  # Render a document title for a search result
  class SearchResultTitleComponent < Blacklight::DocumentTitleComponent
    def initialize(compact:, **args)
      @compact = compact
      super(**args)
    end

    def compact?
      @compact
    end

    # Content for the document actions area
    def actions # rubocop:disable Metrics/CyclomaticComplexity,Metrics/PerceivedComplexity
      return [] unless @actions

      if block_given?
        @has_actions_slot = true
        return super
      end

      (@has_actions_slot && get_slot(:actions)) ||
        ([@document_component&.actions] if @document_component&.actions.present?) ||
        [helpers.render_index_doc_actions(presenter.document, wrapping_class:)]
    end

    def wrapping_class
      'index-document-functions col-md-3 col-xl-2 mb-4 mb-sm-0'
    end
  end
end
