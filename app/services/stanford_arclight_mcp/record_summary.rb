# frozen_string_literal: true

require 'cgi'
require 'uri'

module StanfordArclightMcp
  # Projects an ArcLight document into the compact MCP search result contract.
  class RecordSummary
    STANFORD_PURL_PATTERN = %r{\A(?<purl>https://purl\.stanford\.edu/(?<druid>[a-z]{2}\d{3}[a-z]{2}\d{4}))/?\z}

    def initialize(document:, controller:)
      @document = document
      @controller = controller
    end

    def to_h
      identity_fields.merge(attribution_fields).merge(context_fields).merge(online_fields).compact
    end

    private

    attr_reader :controller, :document

    def identity_fields
      {
        id: document.id,
        url: record_url(document.id),
        title: clean(document.normalized_title) || 'Untitled archival material',
        level: document.level || 'Unknown',
        date: clean(document.normalized_date)
      }
    end

    def attribution_fields
      {
        creators: values('creator_ssim').filter_map { |value| clean(value) }.uniq,
        repository: document.repository || 'Unknown'
      }
    end

    def context_fields
      {
        collection: collection,
        ancestors:,
        unit_ids: values('unitid_ssm').filter_map { |value| clean(value) },
        containers: document.containers,
        description: clean(document.short_description)
      }
    end

    def online_fields
      objects = digital_objects
      {
        has_own_digital_objects: objects.any?,
        has_online_content_in_subtree: document.online_content?,
        digital_objects: objects
      }
    end

    def collection
      return collection_reference(document.id, document.normalized_title) if document.collection?

      collection_parent || collection_reference(document.root, document.collection_name)
    end

    def collection_parent
      ancestors.find { |candidate| candidate[:level].to_s.casecmp?('collection') }&.slice(:id, :url, :title)
    end

    def collection_reference(id, title)
      { id:, url: record_url(id), title: clean(title) || 'Untitled archival material' }
    end

    def ancestors
      @ancestors ||= document.parent_ids.each_index.map do |index|
        collection_reference(document.parent_ids[index], document.parent_labels[index]).merge(
          level: document.parent_levels[index] || 'Unknown'
        )
      end
    end

    def digital_objects
      document.digital_objects.filter_map do |object|
        next unless public_web_url?(object.href)

        { label: clean(object.label) || object.href, url: object.href }.merge(purl_fields(object.href))
      end
    end

    def purl_fields(url)
      match = STANFORD_PURL_PATTERN.match(url)
      return {} unless match

      druid = match[:druid]
      purl = match[:purl]
      { purl:, druid:, iiif_manifest: "#{purl}/iiif3/manifest" }
    end

    def public_web_url?(url)
      uri = URI.parse(url)
      uri.is_a?(URI::HTTP) && uri.host.present?
    rescue URI::InvalidURIError
      false
    end

    def record_url(id)
      controller.solr_document_url(id)
    end

    def clean(value)
      text = CGI.unescapeHTML(ActionController::Base.helpers.strip_tags(value.to_s)).squish
      text.presence
    end

    def values(field)
      Array(document[field]).compact_blank
    end
  end
end
