# frozen_string_literal: true

require 'cgi'

module StanfordArclightMcp
  # Projects one ArcLight document into the fuller MCP record contract.
  class ArchivalRecord
    ACCESS_FIELDS = {
      restrictions: {
        direct: 'accessrestrict_html_tesm',
        ancestor: 'parent_access_restrict_tesm',
        source_prefix: 'parent_access_restrict_source'
      },
      use_restrictions: {
        direct: 'userestrict_html_tesm',
        ancestor: 'parent_access_terms_tesm',
        source_prefix: 'parent_access_terms_source',
        ancestor_includes_self: true
      }
    }.freeze

    def self.requires_ancestor_lookup?(document)
      ACCESS_FIELDS.any? do |_kind, fields|
        ancestor_statement_expected?(document, fields) &&
          !indexed_source_complete?(document, fields[:source_prefix])
      end
    end

    def self.ancestor_statement_expected?(document, fields)
      return false if fields[:ancestor_includes_self] && Array(document[fields[:direct]]).any?(&:present?)

      Array(document[fields[:ancestor]]).any?(&:present?)
    end

    def self.indexed_source_complete?(document, prefix)
      %w[id title level].all? { |field| document["#{prefix}_#{field}_ssi"].present? }
    end

    def initialize(document:, controller:, ancestor_documents: [], cursor: nil,
                   max_content_characters: ArchivalRecordContent::DEFAULT_MAX_CHARACTERS)
      @document = document
      @controller = controller
      @ancestor_documents = ancestor_documents.index_by(&:id)
      @content = ArchivalRecordContent.new(
        document:, cleaner: method(:clean), cursor:, max_characters: max_content_characters
      )
    end

    def to_h = { record: record }

    private

    attr_reader :ancestor_documents, :content, :controller, :document

    def record
      {
        summary: RecordSummary.new(document:, controller:).to_h,
        access: access,
        repository: repository,
        component_count: integer_value('total_component_count_is'),
        online_item_count: integer_value('online_item_count_is')
      }.compact.merge(content.to_h)
    end

    def access
      results = ACCESS_FIELDS.transform_values do |fields|
        access_result(fields)
      end
      status = results.values.all? { |result| result[:complete] } ? 'complete' : 'incomplete'
      { status:, **results.transform_values { |result| result[:statements] } }
    end

    def access_result(fields)
      direct_expected = clean_values(fields[:direct]).any?
      ancestor_expected = self.class.ancestor_statement_expected?(document, fields)
      direct = direct_access_statement(fields[:direct]) if direct_expected
      ancestor = ancestor_access_statement(fields) if ancestor_expected
      {
        statements: [direct, ancestor].compact,
        complete: (!direct_expected || direct.present?) && (!ancestor_expected || ancestor.present?)
      }
    end

    def direct_access_statement(field)
      statement(
        values: clean_values(field),
        source: record_reference(document.id, document.normalized_title, document.level)
      )
    end

    def ancestor_access_statement(fields)
      prefix = fields[:source_prefix]
      values = clean_values(fields[:ancestor])
      statement(
        values:,
        source: source_reference(prefix) || ancestor_source_reference(fields, values)
      )
    end

    def source_reference(prefix)
      record_reference(
        document["#{prefix}_id_ssi"],
        document["#{prefix}_title_ssi"],
        document["#{prefix}_level_ssi"]
      )
    end

    def ancestor_source_reference(fields, inherited_values)
      source = nearest_ancestor_with(fields[:direct], inherited_values)
      return unless source

      record_reference(source.id, source.normalized_title, source.level)
    end

    def nearest_ancestor_with(field, inherited_values)
      document.parent_ids.reverse_each.filter_map { |id| ancestor_documents[id] }
              .find { |ancestor| values_from(ancestor, field) == inherited_values }
    end

    def statement(values:, source:)
      { source:, values: } if values.any? && source
    end

    def record_reference(id, title, level)
      cleaned_id = clean(id)
      cleaned_title = clean(title)
      cleaned_level = clean(level)
      return unless cleaned_id && cleaned_title && cleaned_level

      { id: cleaned_id, url: controller.solr_document_url(cleaned_id), title: cleaned_title, level: cleaned_level }
    end

    def repository
      config = document.repository_config
      {
        name: config&.name || document.repository || 'Unknown',
        url: config&.url,
        visit_note: clean(config&.visit_note),
        requestable: !!document.requestable?
      }.compact
    end

    def integer_value(field) = document[field].presence&.to_i

    def clean_values(field) = Array(document[field]).filter_map { |value| clean(value) }

    def values_from(source_document, field) = Array(source_document[field]).filter_map { |value| clean(value) }

    def clean(value)
      text = CGI.unescapeHTML(ActionController::Base.helpers.strip_tags(value.to_s)).squish
      text.presence
    end
  end
end
