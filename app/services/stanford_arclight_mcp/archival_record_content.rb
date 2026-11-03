# frozen_string_literal: true

require 'base64'
require 'digest'
require 'json'

module StanfordArclightMcp
  # Projects, inventories, and pages the descriptive content of one archival record.
  class ArchivalRecordContent
    DEFAULT_MAX_CHARACTERS = 12_000

    class InvalidCursor < StandardError; end

    def initialize(document:, cleaner:, cursor: nil, max_characters: DEFAULT_MAX_CHARACTERS)
      @document = document
      @cleaner = cleaner
      @cursor = cursor
      @max_characters = max_characters
    end

    def to_h
      page.merge(content_inventory: content_inventory)
    end

    private

    attr_reader :cleaner, :cursor, :document, :max_characters

    def populated_fields
      @populated_fields ||= ArchivalRecordFields::FIELDS.filter_map do |definition|
        values = definition.solr_fields.flat_map { |solr_field| clean_values(solr_field) }.uniq
        { section: definition.section, field: definition.name, label: definition.label, values: } if values.any?
      end
    end

    def content_inventory
      populated_fields.map do |item|
        item.slice(:section, :field, :label).merge(
          value_count: item[:values].length,
          character_count: item[:values].sum(&:length)
        )
      end
    end

    def content_values
      @content_values ||= populated_fields.flat_map do |item|
        item[:values].each_with_index.map do |value, index|
          item.slice(:section, :field, :label).merge(value_index: index, value:)
        end
      end
    end

    # Packs ordered fragments until the caller's descriptive-content budget is exhausted.
    def page
      @page ||= begin
        value_index, offset = cursor_position
        fragments, value_index, offset = pack_fragments(value_index, offset)
        page_result(fragments, value_index, offset)
      end
    end

    def pack_fragments(value_index, offset)
      remaining = positive_max_characters
      fragments = []
      while value_index < content_values.length && remaining.positive?
        next_fragment, consumed = fragment(content_values[value_index], offset, remaining)
        fragments << next_fragment
        remaining -= consumed
        value_index, offset = advance(value_index, next_fragment[:range])
      end
      [fragments, value_index, offset]
    end

    def fragment(item, offset, remaining)
      range_end = offset + [item[:value].length - offset, remaining].min
      fragment = item.except(:value).merge(
        text: item[:value][offset...range_end],
        range: { start: offset, end: range_end, total: item[:value].length }
      )
      [fragment, range_end - offset]
    end

    def advance(value_index, range)
      return [value_index + 1, 0] if range[:end] == range[:total]

      [value_index, range[:end]]
    end

    def page_result(fragments, value_index, offset)
      complete = value_index >= content_values.length
      result = { content: fragments, complete: }
      result[:next_cursor] = encode_cursor(value_index:, offset:) unless complete
      result
    end

    def positive_max_characters
      value = Integer(max_characters)
      raise ArgumentError, 'max_characters must be positive' unless value.positive?

      value
    end

    def cursor_position
      return [0, 0] if cursor.blank?

      payload = decode_cursor
      position = [Integer(payload.fetch('value_index')), Integer(payload.fetch('offset'))]
      validate_position(*position)
      position
    rescue ArgumentError, JSON::ParserError, KeyError
      raise InvalidCursor
    end

    def decode_cursor
      payload = JSON.parse(Base64.urlsafe_decode64(cursor))
      raise InvalidCursor unless payload['id'] == document.id
      raise InvalidCursor unless payload['fingerprint'] == content_fingerprint

      payload
    end

    def validate_position(value_index, offset)
      raise InvalidCursor if value_index.negative? || value_index >= content_values.length
      raise InvalidCursor if offset.negative? || offset >= content_values[value_index][:value].length
    end

    def encode_cursor(value_index:, offset:)
      payload = { id: document.id, fingerprint: content_fingerprint, value_index:, offset: }
      Base64.urlsafe_encode64(payload.to_json, padding: false)
    end

    def content_fingerprint
      @content_fingerprint ||= Digest::SHA256.hexdigest({ projection: 1, content: content_values }.to_json)
    end

    def clean_values(field)
      Array(document[field]).filter_map { |value| cleaner.call(value) }
    end
  end
end
