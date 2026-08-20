# frozen_string_literal: true

module StanfordArclightMcp
  # JSON Schemas shared by the MCP tool definitions.
  # rubocop:disable Metrics/ModuleLength
  module ToolSchemas
    NON_BLANK_STRING = {
      type: 'string',
      minLength: 1,
      pattern: '\\S'
    }.freeze

    FILTER_VALUES = {
      type: 'array',
      items: NON_BLANK_STRING,
      minItems: 1,
      maxItems: 10,
      uniqueItems: true
    }.freeze

    CONTENT_SECTIONS = ArchivalRecordFields::FIELDS.map(&:section).uniq.freeze
    CONTENT_FIELD_NAMES = ArchivalRecordFields::FIELDS.map(&:name).freeze

    COLLECTION = {
      type: 'object',
      additionalProperties: false,
      properties: {
        id: { type: 'string' },
        url: { type: 'string', format: 'uri' },
        title: { type: 'string' }
      },
      required: %w[id url title]
    }.freeze

    ANCESTOR = {
      type: 'object',
      additionalProperties: false,
      properties: COLLECTION[:properties].merge(level: { type: 'string' }),
      required: %w[id url title level]
    }.freeze

    DIGITAL_OBJECT = {
      type: 'object',
      additionalProperties: false,
      properties: {
        label: { type: 'string' },
        url: { type: 'string', format: 'uri' },
        purl: {
          type: 'string',
          format: 'uri',
          description: 'Stable Stanford PURL when this link identifies a Stanford Digital Repository object.'
        },
        druid: {
          type: 'string',
          pattern: '^[a-z]{2}\\d{3}[a-z]{2}\\d{4}$',
          description: 'Stanford Digital Repository identifier extracted from purl.'
        },
        iiif_manifest: {
          type: 'string',
          format: 'uri',
          description: 'Supported IIIF Presentation 3 manifest endpoint for purl.'
        }
      },
      required: %w[label url]
    }.freeze

    ACCESS_STATEMENT = {
      type: 'object',
      additionalProperties: false,
      description: 'Access information attributed to the exact archival record where it is stated.',
      properties: {
        source: { '$ref': '#/$defs/ancestor' },
        values: { '$ref': '#/$defs/textValues' }
      },
      required: %w[source values]
    }.freeze

    CONTENT_INVENTORY_ITEM = {
      type: 'object',
      additionalProperties: false,
      properties: {
        section: { type: 'string', enum: CONTENT_SECTIONS },
        field: { type: 'string', enum: CONTENT_FIELD_NAMES },
        label: { type: 'string' },
        value_count: { type: 'integer', minimum: 1 },
        character_count: { type: 'integer', minimum: 1 }
      },
      required: %w[section field label value_count character_count]
    }.freeze

    CONTENT_FRAGMENT = {
      type: 'object',
      additionalProperties: false,
      properties: {
        section: { type: 'string', enum: CONTENT_SECTIONS },
        field: { type: 'string', enum: CONTENT_FIELD_NAMES },
        label: { type: 'string' },
        value_index: { type: 'integer', minimum: 0 },
        text: { type: 'string', minLength: 1 },
        range: {
          type: 'object',
          additionalProperties: false,
          properties: {
            start: { type: 'integer', minimum: 0 },
            end: { type: 'integer', minimum: 1 },
            total: { type: 'integer', minimum: 1 }
          },
          required: %w[start end total]
        }
      },
      required: %w[section field label value_index text range]
    }.freeze

    RECORD_SUMMARY = {
      type: 'object',
      additionalProperties: false,
      properties: {
        id: { type: 'string' },
        url: { type: 'string', format: 'uri' },
        title: { type: 'string' },
        level: { type: 'string' },
        date: { type: 'string' },
        creators: { type: 'array', items: { type: 'string' }, uniqueItems: true },
        repository: { type: 'string' },
        collection: { '$ref': '#/$defs/collection' },
        ancestors: { type: 'array', items: { '$ref': '#/$defs/ancestor' } },
        unit_ids: { type: 'array', items: { type: 'string' } },
        containers: { type: 'array', items: { type: 'string' } },
        description: { type: 'string', maxLength: 400 },
        has_own_digital_objects: {
          type: 'boolean',
          description: 'True when digital_objects contains at least one public link attached directly to this record.'
        },
        has_online_content_in_subtree: {
          type: 'boolean',
          description: 'True when the index reports online content attached to this record or any descendant.'
        },
        digital_objects: {
          type: 'array',
          items: { '$ref': '#/$defs/digitalObject' },
          description: 'Public online-content links attached directly to this record; links attached to descendants ' \
                       'are not included.'
        }
      },
      required: %w[
        id url title level creators repository collection ancestors unit_ids containers
        has_own_digital_objects has_online_content_in_subtree digital_objects
      ]
    }.freeze

    FACET_VALUE = {
      type: 'object',
      additionalProperties: false,
      properties: {
        value: { type: 'string' },
        count: { type: 'integer', minimum: 0 }
      },
      required: %w[value count]
    }.freeze

    FACET = {
      type: 'object',
      additionalProperties: false,
      properties: {
        key: {
          type: 'string',
          enum: %w[collections creators levels names repositories places access_subjects]
        },
        label: { type: 'string' },
        values: { type: 'array', items: { '$ref': '#/$defs/facetValue' }, maxItems: 20 },
        truncated: {
          type: 'boolean',
          description: 'True when additional matching values were omitted. Retry with a larger facet_limit or ' \
                       'narrow the search.'
        }
      },
      required: %w[key label values truncated]
    }.freeze

    SEARCH_INPUT = {
      type: 'object',
      additionalProperties: false,
      properties: {
        query: NON_BLANK_STRING.merge(
          maxLength: 500,
          description: "Words to find in the selected search_field, or '*' to browse all records selected by filters."
        ),
        search_field: {
          type: 'string',
          enum: %w[keyword name place subject title container call_number],
          default: 'keyword',
          description: 'Part of each record to search. keyword searches broadly; name searches people and ' \
                       'organizations; place searches geographic names; subject searches topics; title searches ' \
                       'titles; container searches box and folder labels; call_number searches archival identifiers.'
        },
        limit: {
          type: 'integer',
          minimum: 1,
          maximum: 20,
          default: 10,
          description: 'Maximum number of records to return.'
        },
        cursor: NON_BLANK_STRING.merge(
          maxLength: 2000,
          description: 'Opaque continuation cursor from a previous response. Reuse it with the same query, ' \
                       'search_field, and filters.'
        ),
        facet_limit: {
          type: 'integer',
          minimum: 1,
          maximum: 20,
          default: 5,
          description: 'Maximum values returned for each refinement facet. Increase when a facet is truncated.'
        },
        filters: {
          type: 'object',
          additionalProperties: false,
          description: 'Values within one array are ORed; different filter properties are ANDed.',
          properties: {
            collection_id: NON_BLANK_STRING.merge(
              description: "Root record ID from a result's collection.id; limits the search to that collection."
            ),
            collections: {
              '$ref': '#/$defs/filterValues',
              description: "Exact, case-sensitive values copied from the response's 'collections' facet."
            },
            creators: {
              '$ref': '#/$defs/filterValues',
              description: "Exact, case-sensitive values copied from the response's 'creators' facet."
            },
            levels: {
              '$ref': '#/$defs/filterValues',
              description: "Exact, case-sensitive level facet values. Use ['Collection'] for collection-level " \
                           "records. Other values can be copied from the response's 'levels' facet."
            },
            names: {
              '$ref': '#/$defs/filterValues',
              description: "Exact, case-sensitive values copied from the response's 'names' facet."
            },
            repositories: {
              '$ref': '#/$defs/filterValues',
              description: "Exact, case-sensitive values copied from the response's 'repositories' facet."
            },
            places: {
              '$ref': '#/$defs/filterValues',
              description: "Exact, case-sensitive values copied from the response's 'places' facet."
            },
            access_subjects: {
              '$ref': '#/$defs/filterValues',
              description: "Exact, case-sensitive values copied from the response's 'access_subjects' facet."
            },
            digital_content_only: {
              type: 'boolean',
              default: false,
              description: 'Return only records with online content attached to the record or any descendant. ' \
                           'Matching hierarchy nodes may have no direct digital_objects.'
            },
            date_range: {
              type: 'object',
              additionalProperties: false,
              description: 'Inclusive indexed-year bounds. Supply either or both bounds.',
              properties: {
                start_year: {
                  type: 'integer', minimum: 0, maximum: 9999, description: 'Earliest year, inclusive.'
                },
                end_year: {
                  type: 'integer', minimum: 0, maximum: 9999, description: 'Latest year, inclusive.'
                }
              },
              anyOf: [
                { required: ['start_year'] },
                { required: ['end_year'] }
              ]
            }
          }
        }
      },
      required: ['query'],
      '$defs': { filterValues: FILTER_VALUES }
    }.freeze

    SEARCH_OUTPUT = {
      type: 'object',
      additionalProperties: false,
      properties: {
        total_count: { type: 'integer', minimum: 0 },
        returned_count: { type: 'integer', minimum: 0, maximum: 20 },
        results: { type: 'array', items: { '$ref': '#/$defs/recordSummary' }, maxItems: 20 },
        next_cursor: {
          type: 'string',
          minLength: 1,
          description: 'Pass this opaque value as cursor to request the next page. Omitted when the page is final.'
        },
        facets: { type: 'array', items: { '$ref': '#/$defs/facet' } }
      },
      required: %w[total_count returned_count results facets],
      '$defs': {
        collection: COLLECTION,
        ancestor: ANCESTOR,
        digitalObject: DIGITAL_OBJECT,
        recordSummary: RECORD_SUMMARY,
        facetValue: FACET_VALUE,
        facet: FACET
      }
    }.freeze

    DETAIL_INPUT = {
      type: 'object',
      additionalProperties: false,
      properties: {
        id: { type: 'string', minLength: 1, maxLength: 500 },
        cursor: NON_BLANK_STRING.merge(
          maxLength: 2000,
          description: 'Opaque continuation cursor from a previous response for the same record.'
        ),
        max_content_characters: {
          type: 'integer',
          minimum: 2000,
          maximum: 24_000,
          default: 12_000,
          description: 'Maximum descriptive-text characters returned on this page. Record context and access ' \
                       'information are returned in addition to this budget.'
        }
      },
      required: ['id']
    }.freeze

    DETAIL_OUTPUT = {
      type: 'object',
      additionalProperties: false,
      properties: {
        record: {
          type: 'object',
          additionalProperties: false,
          properties: {
            summary: { '$ref': '#/$defs/recordSummary' },
            access: {
              type: 'object',
              additionalProperties: false,
              description: 'Access information grouped by source record. More than one restriction may apply.',
              properties: {
                status: {
                  type: 'string',
                  enum: %w[complete incomplete],
                  description: 'Incomplete means indexed access text exists but its exact source could not be ' \
                               'established, so that unattributed text is not returned as a statement.'
                },
                restrictions: {
                  type: 'array',
                  items: { '$ref': '#/$defs/accessStatement' },
                  description: 'Conditions governing access stated on this record and its applicable ancestor.'
                },
                use_restrictions: {
                  type: 'array',
                  items: { '$ref': '#/$defs/accessStatement' },
                  description: 'Conditions governing use stated on this record or its applicable ancestor.'
                }
              },
              required: %w[status restrictions use_restrictions]
            },
            repository: {
              type: 'object',
              additionalProperties: false,
              properties: {
                name: { type: 'string' },
                url: { type: 'string', format: 'uri' },
                visit_note: { type: 'string' },
                requestable: { type: 'boolean' }
              },
              required: %w[name requestable]
            },
            component_count: { type: 'integer', minimum: 0 },
            online_item_count: { type: 'integer', minimum: 0 },
            content_inventory: {
              type: 'array',
              items: { '$ref': '#/$defs/contentInventoryItem' },
              description: 'Every populated descriptive field supported by this projection, including content ' \
                           'that is returned on another page. A supported field absent from this inventory is not ' \
                           'populated on the indexed record.'
            },
            content: {
              type: 'array',
              items: { '$ref': '#/$defs/contentFragment' },
              description: 'Ordered, faithful fragments of indexed descriptive values. Concatenate fragments with ' \
                           'the same field and value_index in range order to reconstruct a paged value.'
            },
            complete: {
              type: 'boolean',
              description: 'True when all fields named by content_inventory have been returned through this page.'
            },
            next_cursor: {
              type: 'string',
              minLength: 1,
              description: 'Pass this opaque value with the same record ID to retrieve the next content page.'
            }
          },
          required: %w[summary access repository content_inventory content complete]
        }
      },
      required: ['record'],
      '$defs': {
        textValues: { type: 'array', items: { type: 'string' } },
        accessStatement: ACCESS_STATEMENT,
        contentInventoryItem: CONTENT_INVENTORY_ITEM,
        contentFragment: CONTENT_FRAGMENT,
        collection: COLLECTION,
        ancestor: ANCESTOR,
        digitalObject: DIGITAL_OBJECT,
        recordSummary: RECORD_SUMMARY
      }
    }.freeze
  end
  # rubocop:enable Metrics/ModuleLength
end
