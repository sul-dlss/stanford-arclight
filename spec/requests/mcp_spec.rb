# frozen_string_literal: true

require 'rails_helper'
require 'json_schemer'

RSpec.describe 'MCP endpoint' do
  def post_mcp(message, headers: {})
    post '/mcp',
         params: message.to_json,
         headers: {
           'Content-Type' => 'application/json',
           'Accept' => 'application/json, text/event-stream'
         }.merge(headers)
  end

  describe 'POST /mcp' do
    it 'initializes an MCP session' do
      post_mcp({
                 jsonrpc: '2.0',
                 id: 'initialize-1',
                 method: 'initialize',
                 params: {
                   protocolVersion: '2025-11-25',
                   capabilities: {},
                   clientInfo: { name: 'request-spec', version: '1.0.0' }
                 }
               })

      expect(response).to have_http_status(:ok)
      expect(response.parsed_body).to include(
        'jsonrpc' => '2.0',
        'id' => 'initialize-1',
        'result' => include(
          'protocolVersion' => '2025-11-25',
          'serverInfo' => include('name' => 'stanford_arclight', 'version' => '0.1.0'),
          'capabilities' => include('tools')
        )
      )
    end

    it 'accepts notifications without a response body' do
      post_mcp(
        { jsonrpc: '2.0', method: 'notifications/initialized' },
        headers: { 'MCP-Protocol-Version' => '2025-11-25' }
      )

      expect(response).to have_http_status(:accepted)
      expect(response.body).to be_empty
    end

    it 'lists the archival discovery tools and their schemas' do
      post_mcp(
        { jsonrpc: '2.0', id: 'tools-1', method: 'tools/list' },
        headers: { 'MCP-Protocol-Version' => '2025-11-25' }
      )

      expect(response).to have_http_status(:ok)
      tools = response.parsed_body.dig('result', 'tools')
      expect(tools.pluck('name')).to eq(%w[search_archival_materials get_archival_record])

      search_tool = tools.first
      expect(search_tool).to include(
        'description' => 'Search Stanford archival collections and their hierarchical components. Results include ' \
                         'collection and ancestor context, containers, online content, and facets for refining ' \
                         "subsequent searches. Use '*' as the query to browse all records, optionally constrained " \
                         'by filters.',
        'annotations' => include(
          'readOnlyHint' => true,
          'destructiveHint' => false,
          'idempotentHint' => true,
          'openWorldHint' => false
        ),
        'inputSchema' => include(
          'required' => ['query'],
          'properties' => include(
            'search_field' => include(
              'enum' => %w[keyword name place subject title container call_number]
            ),
            'limit' => include('minimum' => 1, 'maximum' => 20),
            'cursor' => include('type' => 'string'),
            'facet_limit' => include('minimum' => 1, 'maximum' => 20, 'default' => 5),
            'filters' => include(
              'properties' => include(
                'levels' => include(
                  'description' => "Exact, case-sensitive level facet values. Use ['Collection'] for " \
                                   "collection-level records. Other values can be copied from the response's " \
                                   "'levels' facet."
                )
              )
            )
          )
        ),
        'outputSchema' => include(
          'properties' => include('next_cursor' => include('type' => 'string')),
          'required' => include('total_count', 'returned_count', 'results', 'facets')
        )
      )

      output_schema = search_tool.fetch('outputSchema')
      echoed_fields = %w[query search_field applied_filters]
      expect(output_schema.fetch('properties').keys).not_to include(*echoed_fields)
      expect(output_schema.fetch('required')).not_to include(*echoed_fields)

      expect(search_tool.dig('inputSchema', 'properties', 'filters', 'properties', 'digital_content_only')).to include(
        'description' => 'Return only records with online content attached to the record or any descendant. ' \
                         'Matching hierarchy nodes may have no direct digital_objects.'
      )
      record_properties = search_tool.dig('outputSchema', '$defs', 'recordSummary', 'properties')
      expect(record_properties.fetch('has_own_digital_objects')).to include(
        'description' => 'True when digital_objects contains at least one public link attached directly to this record.'
      )
      expect(record_properties.fetch('has_online_content_in_subtree')).to include(
        'description' => 'True when the index reports online content attached to this record or any descendant.'
      )
      expect(record_properties.fetch('digital_objects')).to include(
        'description' => 'Public online-content links attached directly to this record; ' \
                         'links attached to descendants are not included.'
      )

      detail_tool = tools.second
      expect(detail_tool).to include(
        'description' => 'Retrieve every populated descriptive field supported by the indexed ArcLight record, ' \
                         'grouped by archival purpose, with exact access sources. Long descriptions are returned ' \
                         'in bounded, deterministic pages without silent truncation.'
      )
      expect(detail_tool.fetch('inputSchema')).to include(
        'properties' => include(
          'cursor' => include('type' => 'string'),
          'max_content_characters' => include('minimum' => 2000, 'maximum' => 24_000, 'default' => 12_000)
        )
      )
      expect(detail_tool.dig('outputSchema', 'properties', 'record', 'properties')).to include(
        'content_inventory' => include('type' => 'array'),
        'content' => include('type' => 'array'),
        'complete' => include('type' => 'boolean'),
        'next_cursor' => include('type' => 'string')
      )
      detail_field_names = detail_tool.dig(
        'outputSchema', '$defs', 'contentInventoryItem', 'properties', 'field', 'enum'
      )
      expect(detail_field_names).to include(
        'abstract', 'scope_and_contents', 'acquisition_information', 'physical_description', 'related_materials',
        'preferred_citation', 'subjects'
      )

      input_properties = search_tool.dig('inputSchema', 'properties')
      expect(input_properties.transform_values { |schema| schema['description'] }).to include(
        'query' => "Words to find in the selected search_field, or '*' to browse all records selected by filters.",
        'search_field' => 'Part of each record to search. keyword searches broadly; name searches people and ' \
                          'organizations; place searches geographic names; subject searches topics; title searches ' \
                          'titles; container searches box and folder labels; ' \
                          'call_number searches archival identifiers.',
        'cursor' => 'Opaque continuation cursor from a previous response. ' \
                    'Reuse it with the same query, search_field, and filters.'
      )
      filter_properties = input_properties.dig('filters', 'properties')
      expect(filter_properties.transform_values { |schema| schema['description'] }).to include(
        'collection_id' => "Root record ID from a result's collection.id; limits the search to that collection.",
        'collections' => "Exact, case-sensitive values copied from the response's 'collections' facet.",
        'creators' => "Exact, case-sensitive values copied from the response's 'creators' facet.",
        'names' => "Exact, case-sensitive values copied from the response's 'names' facet.",
        'repositories' => "Exact, case-sensitive values copied from the response's 'repositories' facet.",
        'places' => "Exact, case-sensitive values copied from the response's 'places' facet.",
        'access_subjects' => "Exact, case-sensitive values copied from the response's 'access_subjects' facet.",
        'date_range' => 'Inclusive indexed-year bounds. Supply either or both bounds.'
      )
      expect(filter_properties.dig('date_range', 'properties')).to include(
        'start_year' => include('description' => 'Earliest year, inclusive.'),
        'end_year' => include('description' => 'Latest year, inclusive.')
      )
    end

    it 'searches archival materials with hierarchy and digital-object context' do
      output_schema = advertised_output_schema('search_archival_materials')
      solr_connection = instance_double(RSolr::Client)
      allow(RSolr).to receive(:connect).and_return(solr_connection)
      allow(solr_connection).to receive(:send_and_receive).and_return(
        {
          'responseHeader' => { 'status' => 0, 'params' => {} },
          'response' => {
            'numFound' => 1,
            'start' => 0,
            'docs' => [
              {
                'id' => 'sc0097_aspace_ref33_thm',
                '_root_' => 'sc0097',
                'normalized_title_ssm' => ['1987 Oct 9'],
                'normalized_date_ssm' => ['1987 Oct 9'],
                'level_ssm' => ['File'],
                'parent_ids_ssim' => %w[sc0097 sc0097_aspace_ref24_kgz],
                'parent_unittitles_ssm' => [
                  'Donald E. Knuth papers, 1962-2018',
                  'Addenda, 1998-154 (videorecordings)'
                ],
                'parent_levels_ssm' => %w[collection Series],
                'unitid_ssm' => ['174.5'],
                'repository_ssim' => ['University Archives'],
                'containers_ssim' => ['Box 1'],
                'has_online_content_ssim' => ['true'],
                'digital_objects_ssm' => [
                  {
                    label: 'Comments on student answers (2)', href: 'https://purl.stanford.edu/vz772ry6707/'
                  }.to_json,
                  { label: 'Unsafe object', href: 'javascript:alert(1)' }.to_json
                ]
              }
            ]
          },
          'facet_counts' => { 'facet_fields' => {} }
        }
      )

      post_mcp(
        {
          jsonrpc: '2.0',
          id: 'search-1',
          method: 'tools/call',
          params: {
            name: 'search_archival_materials',
            arguments: { query: 'Knuth', limit: 5 }
          }
        },
        headers: { 'MCP-Protocol-Version' => '2025-11-25' }
      )

      expect(response).to have_http_status(:ok)
      result = response.parsed_body.fetch('result')
      structured_content = result.fetch('structuredContent')
      expect(JSONSchemer.schema(output_schema).validate(structured_content).to_a).to be_empty
      expect(structured_content).to include(
        'total_count' => 1,
        'returned_count' => 1,
        'facets' => []
      )
      expect(structured_content.keys).not_to include('query', 'search_field', 'applied_filters')
      expect(structured_content.fetch('results').first).to include(
        'id' => 'sc0097_aspace_ref33_thm',
        'url' => 'http://www.example.com/catalog/sc0097_aspace_ref33_thm',
        'title' => '1987 Oct 9',
        'level' => 'File',
        'collection' => {
          'id' => 'sc0097',
          'url' => 'http://www.example.com/catalog/sc0097',
          'title' => 'Donald E. Knuth papers, 1962-2018'
        },
        'containers' => ['Box 1'],
        'unit_ids' => ['174.5'],
        'has_own_digital_objects' => true,
        'has_online_content_in_subtree' => true,
        'digital_objects' => [
          {
            'label' => 'Comments on student answers (2)',
            'url' => 'https://purl.stanford.edu/vz772ry6707/',
            'purl' => 'https://purl.stanford.edu/vz772ry6707',
            'druid' => 'vz772ry6707',
            'iiif_manifest' => 'https://purl.stanford.edu/vz772ry6707/iiif3/manifest'
          }
        ]
      )
      expect(JSON.parse(result.dig('content', 0, 'text'))).to eq(structured_content)
    end

    it 'returns schema-valid digital-object URLs' do
      solr_connection = instance_double(RSolr::Client)
      allow(RSolr).to receive(:connect).and_return(solr_connection)
      allow(solr_connection).to receive(:send_and_receive).and_return(
        {
          'responseHeader' => { 'status' => 0, 'params' => {} },
          'response' => {
            'numFound' => 1,
            'start' => 0,
            'docs' => [
              {
                'id' => 'per-aclun',
                '_root_' => 'per-aclun',
                'normalized_title_ssm' => [
                  'The Newsletter of the American Civil Liberties Union of Northern California collection'
                ],
                'level_ssm' => ['Collection'],
                'component_level_isim' => [0],
                'repository_ssim' => ['Manuscripts'],
                'has_online_content_ssim' => ['true'],
                'digital_objects_ssm' => [
                  {
                    label: 'ACLU of Northern California News',
                    href: "\n\nhttps://searchworks.stanford.edu/catalog?f[collection][]=in00000325540"
                  }.to_json
                ]
              }
            ]
          },
          'facet_counts' => { 'facet_fields' => {} }
        }
      )

      post_mcp(
        {
          jsonrpc: '2.0',
          id: 'search-encoded-url-1',
          method: 'tools/call',
          params: {
            name: 'search_archival_materials',
            arguments: { query: 'civil', filters: { levels: ['Collection'] } }
          }
        },
        headers: { 'MCP-Protocol-Version' => '2025-11-25' }
      )

      expect(response.parsed_body.dig(
               'result', 'structuredContent', 'results', 0, 'digital_objects', 0
             )).to eq(
               'label' => 'ACLU of Northern California News',
               'url' => 'https://searchworks.stanford.edu/catalog?f%5Bcollection%5D%5B%5D=in00000325540'
             )
    end

    it 'distinguishes direct digital objects from online content in descendants' do
      solr_connection = instance_double(RSolr::Client)
      allow(RSolr).to receive(:connect).and_return(solr_connection)
      allow(solr_connection).to receive(:send_and_receive).and_return(
        solr_response(
          documents: [collection_document('collection').merge('has_online_content_ssim' => ['true'])],
          total: 1,
          next_cursor: '*'
        )
      )

      post_mcp(
        {
          jsonrpc: '2.0',
          id: 'search-descendant-online-content-1',
          method: 'tools/call',
          params: { name: 'search_archival_materials', arguments: { query: 'collection' } }
        },
        headers: { 'MCP-Protocol-Version' => '2025-11-25' }
      )

      expect(response.parsed_body.dig('result', 'structuredContent', 'results', 0)).to include(
        'has_own_digital_objects' => false,
        'has_online_content_in_subtree' => true,
        'digital_objects' => []
      )
    end

    it 'continues a search from the returned cursor' do
      solr_connection = instance_double(RSolr::Client)
      allow(RSolr).to receive(:connect).and_return(solr_connection)
      allow(solr_connection).to receive(:send_and_receive) do |_path, options|
        params = options.fetch(:params)
        expect(params.fetch(:sort)).to end_with(', id asc')
        documents = case params.fetch(:cursorMark)
                    when '*'
                      [collection_document('collection-1'), collection_document('collection-2')]
                    when 'second-page'
                      [collection_document('collection-3')]
                    else
                      raise 'Unexpected search cursor'
                    end
        next_cursor = params.fetch(:cursorMark) == '*' ? 'second-page' : 'last-page'

        solr_response(documents:, total: 3, next_cursor:)
      end

      post_mcp(
        {
          jsonrpc: '2.0',
          id: 'search-page-1',
          method: 'tools/call',
          params: { name: 'search_archival_materials', arguments: { query: '*', limit: 2 } }
        },
        headers: { 'MCP-Protocol-Version' => '2025-11-25' }
      )

      first_page = response.parsed_body.dig('result', 'structuredContent')
      cursor = first_page.fetch('next_cursor')

      post_mcp(
        {
          jsonrpc: '2.0',
          id: 'search-page-2',
          method: 'tools/call',
          params: {
            name: 'search_archival_materials',
            arguments: { query: '*', limit: 2, cursor: }
          }
        },
        headers: { 'MCP-Protocol-Version' => '2025-11-25' }
      )

      second_page = response.parsed_body.dig('result', 'structuredContent')
      expect(
        [first_page.fetch('results').pluck('id'), second_page.fetch('results').pluck('id'), second_page['next_cursor']]
      ).to eq([%w[collection-1 collection-2], ['collection-3'], nil])
    end

    it 'maps archival filters and returns refinement facets' do
      solr_connection = instance_double(RSolr::Client)
      allow(RSolr).to receive(:connect).and_return(solr_connection)
      allow(solr_connection).to receive(:send_and_receive).and_return(
        {
          'responseHeader' => { 'status' => 0, 'params' => {} },
          'response' => { 'numFound' => 0, 'start' => 0, 'docs' => [] },
          'facet_counts' => {
            'facet_fields' => {
              'collection_ssim' => ['Donald E. Knuth papers, 1962-2018', 7],
              'creator_ssim' => ['Knuth, Donald Ervin, 1938-', 5],
              'level_ssim' => ['File', 4]
            }
          }
        }
      )

      filters = {
        collection_id: 'sc0097',
        creators: ['Knuth, Donald Ervin, 1938-'],
        levels: %w[File Item],
        digital_content_only: true,
        date_range: { start_year: 1980, end_year: 1990 }
      }
      post_mcp(
        {
          jsonrpc: '2.0',
          id: 'search-filters-1',
          method: 'tools/call',
          params: {
            name: 'search_archival_materials',
            arguments: { query: 'Knuth', search_field: 'name', limit: 20, filters: }
          }
        },
        headers: { 'MCP-Protocol-Version' => '2025-11-25' }
      )

      expect(response).to have_http_status(:ok)
      structured_content = response.parsed_body.dig('result', 'structuredContent')
      expect(structured_content).to include(
        'facets' => [
          {
            'key' => 'collections',
            'label' => 'Collection',
            'truncated' => false,
            'values' => [{ 'value' => 'Donald E. Knuth papers, 1962-2018', 'count' => 7 }]
          },
          {
            'key' => 'creators',
            'label' => 'Creators',
            'truncated' => false,
            'values' => [{ 'value' => 'Knuth, Donald Ervin, 1938-', 'count' => 5 }]
          },
          {
            'key' => 'levels',
            'label' => 'Level',
            'truncated' => false,
            'values' => [{ 'value' => 'File', 'count' => 4 }]
          }
        ]
      )
      expect(structured_content.keys).not_to include('query', 'search_field', 'applied_filters')

      expect(solr_connection).to have_received(:send_and_receive) do |_path, options|
        params = options.fetch(:params)
        expect(params).to include(rows: 20, qf: '${qf_name}', pf: '${pf_name}')
        expect(params.fetch(:fq)).to include(
          '{!term f=_root_}sc0097',
          '{!term f=creator_ssim}Knuth, Donald Ervin, 1938-',
          '{!lucene}{!query v=$f_inclusive.level.0} OR {!query v=$f_inclusive.level.1}',
          'has_online_content_ssim:true',
          'date_range_isim:[1980 TO 1990]'
        )
        expect(params).to include(
          'f_inclusive.level.0' => '{!term f=level_ssim}File',
          'f_inclusive.level.1' => '{!term f=level_ssim}Item'
        )
        expect(params.fetch(:q)).to eq('Knuth')
      end
    end

    it 'reports when refinement facet values are truncated' do
      solr_connection = instance_double(RSolr::Client)
      allow(RSolr).to receive(:connect).and_return(solr_connection)
      allow(solr_connection).to receive(:send_and_receive).and_return(
        {
          'responseHeader' => { 'status' => 0, 'params' => {} },
          'response' => { 'numFound' => 0, 'start' => 0, 'docs' => [] },
          'facet_counts' => {
            'facet_fields' => {
              'level_ssim' => ['Collection', 100, 'Series', 90, 'Subseries', 80, 'File', 70, 'Item', 60, 'Other', 50]
            }
          }
        }
      )

      post_mcp(
        {
          jsonrpc: '2.0',
          id: 'search-truncated-facets',
          method: 'tools/call',
          params: { name: 'search_archival_materials', arguments: { query: '*' } }
        },
        headers: { 'MCP-Protocol-Version' => '2025-11-25' }
      )

      levels = response.parsed_body.dig('result', 'structuredContent', 'facets').sole
      expect(levels).to include(
        'key' => 'levels',
        'truncated' => true,
        'values' => [
          { 'value' => 'Collection', 'count' => 100 },
          { 'value' => 'Series', 'count' => 90 },
          { 'value' => 'Subseries', 'count' => 80 },
          { 'value' => 'File', 'count' => 70 },
          { 'value' => 'Item', 'count' => 60 }
        ]
      )
      expect(solr_connection).to have_received(:send_and_receive) do |_path, options|
        expect(options.fetch(:params)).to include('f.level_ssim.facet.limit': 6)
      end
    end

    it 'accepts a larger facet limit to discover additional values' do
      solr_connection = instance_double(RSolr::Client)
      allow(RSolr).to receive(:connect).and_return(solr_connection)
      allow(solr_connection).to receive(:send_and_receive).and_return(
        {
          'responseHeader' => { 'status' => 0, 'params' => {} },
          'response' => { 'numFound' => 0, 'start' => 0, 'docs' => [] },
          'facet_counts' => {
            'facet_fields' => {
              'level_ssim' => ['Collection', 100, 'Series', 90, 'Subseries', 80, 'File', 70, 'Item', 60, 'Other', 50]
            }
          }
        }
      )

      post_mcp(
        {
          jsonrpc: '2.0',
          id: 'search-expanded-facets',
          method: 'tools/call',
          params: {
            name: 'search_archival_materials',
            arguments: { query: '*', facet_limit: 10 }
          }
        },
        headers: { 'MCP-Protocol-Version' => '2025-11-25' }
      )

      levels = response.parsed_body.dig('result', 'structuredContent', 'facets').sole
      expect([levels.fetch('values').pluck('value'), levels.fetch('truncated')]).to eq(
        [%w[Collection Series Subseries File Item Other], false]
      )
      expect(solr_connection).to have_received(:send_and_receive) do |_path, options|
        expect(options.fetch(:params)).to include('f.level_ssim.facet.limit': 11)
      end
    end

    it 'gets display-complete descriptive and repository access details for one record' do
      output_schema = advertised_output_schema('get_archival_record')
      solr_connection = instance_double(RSolr::Client)
      allow(RSolr).to receive(:connect).and_return(solr_connection)
      allow(solr_connection).to receive(:send_and_receive).and_return(
        {
          'responseHeader' => { 'status' => 0, 'params' => {} },
          'response' => {
            'numFound' => 1,
            'start' => 0,
            'docs' => [
              {
                'id' => 'sc0097',
                '_root_' => 'sc0097',
                'normalized_title_ssm' => ['Donald E. Knuth papers, 1962-2018'],
                'normalized_date_ssm' => ['1962-2018'],
                'level_ssm' => ['Collection'],
                'component_level_isim' => [0],
                'creator_ssim' => ['Knuth, Donald Ervin, 1938-'],
                'repository_ssm' => ['University Archives'],
                'extent_ssm' => ['1038 Linear Feet'],
                'language_ssim' => ['English'],
                'scopecontent_html_tesm' => ['<p>Research files &amp; correspondence.</p>'],
                'bioghist_html_tesm' => ['<p>Computer scientist.</p>'],
                'arrangement_html_tesm' => ['<p>Arranged in series.</p>'],
                'acqinfo_ssim' => ['Gift of Donald E. Knuth.'],
                'relatedmaterial_html_tesm' => ['<p>See also related oral histories.</p>'],
                'prefercite_html_tesm' => ['<p>Donald E. Knuth papers, Stanford University Archives.</p>'],
                'accessrestrict_html_tesm' => ['<p>Open for research.</p>'],
                'userestrict_html_tesm' => ['<p>Copyright retained.</p>'],
                'total_component_count_is' => 1140,
                'online_item_count_is' => 12,
                'has_online_content_ssim' => ['false']
              }
            ]
          }
        }
      )

      post_mcp(
        {
          jsonrpc: '2.0',
          id: 'detail-1',
          method: 'tools/call',
          params: { name: 'get_archival_record', arguments: { id: 'sc0097' } }
        },
        headers: { 'MCP-Protocol-Version' => '2025-11-25' }
      )

      expect(response).to have_http_status(:ok)
      result = response.parsed_body.fetch('result')
      record = result.dig('structuredContent', 'record')
      expect(JSONSchemer.schema(output_schema).validate(result.fetch('structuredContent')).to_a).to be_empty
      expect(record).to include(
        'summary' => include(
          'id' => 'sc0097',
          'url' => 'http://www.example.com/catalog/sc0097',
          'collection' => include('id' => 'sc0097')
        ),
        'access' => {
          'status' => 'complete',
          'restrictions' => [
            {
              'source' => {
                'id' => 'sc0097',
                'url' => 'http://www.example.com/catalog/sc0097',
                'title' => 'Donald E. Knuth papers, 1962-2018',
                'level' => 'Collection'
              },
              'values' => ['Open for research.']
            }
          ],
          'use_restrictions' => [
            {
              'source' => {
                'id' => 'sc0097',
                'url' => 'http://www.example.com/catalog/sc0097',
                'title' => 'Donald E. Knuth papers, 1962-2018',
                'level' => 'Collection'
              },
              'values' => ['Copyright retained.']
            }
          ]
        },
        'repository' => include(
          'name' => 'University Archives',
          'url' => 'https://library.stanford.edu/libraries/special-collections',
          'requestable' => true
        ),
        'component_count' => 1140,
        'online_item_count' => 12,
        'complete' => true
      )
      expect(record.fetch('content_inventory').pluck('field')).to eq(
        %w[
          scope_and_contents biographical_historical arrangement extent languages acquisition_information
          related_materials preferred_citation
        ]
      )
      expect(record.fetch('content')).to include(
        include(
          'section' => 'administrative',
          'field' => 'acquisition_information',
          'text' => 'Gift of Donald E. Knuth.'
        ),
        include(
          'section' => 'related_materials',
          'field' => 'related_materials',
          'text' => 'See also related oral histories.'
        ),
        include(
          'section' => 'citation',
          'field' => 'preferred_citation',
          'text' => 'Donald E. Knuth papers, Stanford University Archives.'
        )
      )
      expect(JSON.parse(result.dig('content', 0, 'text'))).to eq(result.fetch('structuredContent'))
    end

    it 'continues a large archival description without losing content' do
      output_schema = advertised_output_schema('get_archival_record')
      long_description = 'a' * 2500
      solr_connection = instance_double(RSolr::Client)
      allow(RSolr).to receive(:connect).and_return(solr_connection)
      allow(solr_connection).to receive(:send_and_receive).and_return(
        {
          'responseHeader' => { 'status' => 0, 'params' => {} },
          'response' => {
            'numFound' => 1,
            'start' => 0,
            'docs' => [
              {
                'id' => 'large-record',
                '_root_' => 'large-record',
                'normalized_title_ssm' => ['Large record'],
                'level_ssm' => ['Collection'],
                'component_level_isim' => [0],
                'repository_ssm' => ['University Archives'],
                'scopecontent_html_tesm' => [long_description],
                'has_online_content_ssim' => ['false']
              }
            ]
          }
        }
      )

      post_mcp(
        {
          jsonrpc: '2.0',
          id: 'detail-large-1',
          method: 'tools/call',
          params: {
            name: 'get_archival_record',
            arguments: { id: 'large-record', max_content_characters: 2000 }
          }
        },
        headers: { 'MCP-Protocol-Version' => '2025-11-25' }
      )
      first = response.parsed_body.dig('result', 'structuredContent')
      cursor = first.dig('record', 'next_cursor')

      post_mcp(
        {
          jsonrpc: '2.0',
          id: 'detail-large-2',
          method: 'tools/call',
          params: {
            name: 'get_archival_record',
            arguments: { id: 'large-record', cursor:, max_content_characters: 2000 }
          }
        },
        headers: { 'MCP-Protocol-Version' => '2025-11-25' }
      )
      second = response.parsed_body.dig('result', 'structuredContent')

      expect(JSONSchemer.schema(output_schema).validate(first).to_a).to be_empty
      expect(JSONSchemer.schema(output_schema).validate(second).to_a).to be_empty
      expect(first.fetch('record')).to include('complete' => false)
      expect(first.dig('record', 'content', 0)).to include(
        'text' => 'a' * 2000,
        'range' => { 'start' => 0, 'end' => 2000, 'total' => 2500 }
      )
      expect(second.fetch('record')).to include('complete' => true)
      expect(second.dig('record', 'content', 0)).to include(
        'text' => 'a' * 500,
        'range' => { 'start' => 2000, 'end' => 2500, 'total' => 2500 }
      )
      expect(second.dig('record', 'next_cursor')).to be_nil
    end

    it 'resolves inherited access provenance from ancestors on an unreindexed record' do
      solr_connection = instance_double(RSolr::Client)
      allow(RSolr).to receive(:connect).and_return(solr_connection)
      allow(solr_connection).to receive(:send_and_receive).and_return(
        {
          'responseHeader' => { 'status' => 0, 'params' => {} },
          'response' => {
            'numFound' => 1,
            'start' => 0,
            'docs' => [
              {
                'id' => 'collection_series_folder',
                '_root_' => 'collection',
                'normalized_title_ssm' => ['Correspondence'],
                'level_ssm' => ['Folder'],
                'component_level_isim' => [2],
                'parent_ids_ssim' => %w[collection collection_series],
                'parent_unittitles_ssm' => ['Example papers', 'Series 1'],
                'parent_levels_ssm' => %w[Collection Series],
                'repository_ssm' => ['University Archives'],
                'parent_access_restrict_tesm' => ['Series is closed until 2035.'],
                'has_online_content_ssim' => ['false']
              }
            ]
          }
        },
        {
          'responseHeader' => { 'status' => 0, 'params' => {} },
          'response' => {
            'numFound' => 2,
            'start' => 0,
            'docs' => [
              {
                'id' => 'collection',
                'normalized_title_ssm' => ['Example papers'],
                'level_ssm' => ['Collection']
              },
              {
                'id' => 'collection_series',
                'normalized_title_ssm' => ['Series 1'],
                'level_ssm' => ['Series'],
                'accessrestrict_html_tesm' => ['Series is closed until 2035.']
              }
            ]
          }
        }
      )

      post_mcp(
        {
          jsonrpc: '2.0',
          id: 'detail-old-index-1',
          method: 'tools/call',
          params: { name: 'get_archival_record', arguments: { id: 'collection_series_folder' } }
        },
        headers: { 'MCP-Protocol-Version' => '2025-11-25' }
      )

      restriction = response.parsed_body.dig(
        'result', 'structuredContent', 'record', 'access', 'restrictions', 0
      )
      expect(restriction).to include(
        'source' => {
          'id' => 'collection_series',
          'url' => 'http://www.example.com/catalog/collection_series',
          'title' => 'Series 1',
          'level' => 'Series'
        },
        'values' => ['Series is closed until 2035.']
      )
      expect(solr_connection).to have_received(:send_and_receive).twice
    end

    it 'returns a tool error when the archival record does not exist' do
      solr_connection = instance_double(RSolr::Client)
      allow(RSolr).to receive(:connect).and_return(solr_connection)
      allow(solr_connection).to receive(:send_and_receive).and_return(
        {
          'responseHeader' => { 'status' => 0, 'params' => {} },
          'response' => { 'numFound' => 0, 'start' => 0, 'docs' => [] }
        }
      )

      post_mcp(
        {
          jsonrpc: '2.0',
          id: 'detail-missing-1',
          method: 'tools/call',
          params: { name: 'get_archival_record', arguments: { id: 'missing' } }
        },
        headers: { 'MCP-Protocol-Version' => '2025-11-25' }
      )

      expect(response).to have_http_status(:ok)
      expect(response.parsed_body.fetch('result')).to include(
        'isError' => true,
        'content' => [include('type' => 'text', 'text' => 'Archival record not found.')]
      )
    end

    it 'rejects invalid tool arguments before searching' do
      allow(RSolr).to receive(:connect)

      post_mcp(
        {
          jsonrpc: '2.0',
          id: 'invalid-arguments-1',
          method: 'tools/call',
          params: {
            name: 'search_archival_materials',
            arguments: { query: '', limit: 100 }
          }
        },
        headers: { 'MCP-Protocol-Version' => '2025-11-25' }
      )

      expect(response).to have_http_status(:ok)
      expect(response.parsed_body.fetch('result')).to include('isError' => true)
      expect(RSolr).not_to have_received(:connect)
    end

    it 'rejects an inverted date range before searching' do
      allow(RSolr).to receive(:connect)

      post_mcp(
        {
          jsonrpc: '2.0',
          id: 'inverted-date-range-1',
          method: 'tools/call',
          params: {
            name: 'search_archival_materials',
            arguments: {
              query: '*',
              filters: { date_range: { start_year: 2000, end_year: 1900 } }
            }
          }
        },
        headers: { 'MCP-Protocol-Version' => '2025-11-25' }
      )

      expect(response).to have_http_status(:ok)
      error_text = 'date_range.start_year must be less than or equal to date_range.end_year.'
      expect(response.parsed_body.fetch('result')).to include(
        'isError' => true,
        'content' => [include('type' => 'text', 'text' => error_text)]
      )
      expect(RSolr).not_to have_received(:connect)
    end

    it 'rejects whitespace-only search arguments before searching' do
      allow(RSolr).to receive(:connect)
      invalid_arguments = [
        { query: '   ' },
        { query: '*', cursor: '   ' },
        { query: '*', filters: { collection_id: '   ' } },
        { query: '*', filters: { creators: ['   '] } }
      ]

      invalid_arguments.each_with_index do |arguments, index|
        post_mcp(
          {
            jsonrpc: '2.0',
            id: "blank-arguments-#{index}",
            method: 'tools/call',
            params: { name: 'search_archival_materials', arguments: }
          },
          headers: { 'MCP-Protocol-Version' => '2025-11-25' }
        )

        expect(response.parsed_body.fetch('result')).to include('isError' => true)
      end
      expect(RSolr).not_to have_received(:connect)
    end

    it 'does not expose upstream failures to clients' do
      allow(RSolr).to receive(:connect).and_raise(StandardError, 'private Solr host and secret')

      post_mcp(
        {
          jsonrpc: '2.0',
          id: 'upstream-error-1',
          method: 'tools/call',
          params: {
            name: 'search_archival_materials',
            arguments: { query: 'Knuth' }
          }
        },
        headers: { 'MCP-Protocol-Version' => '2025-11-25' }
      )

      expect(response).to have_http_status(:ok)
      body = response.parsed_body.to_json
      expect(body).to include('Internal error')
      expect(body).not_to include('private Solr host and secret')
    end

    it 'rejects cross-origin browser requests' do
      post_mcp(
        { jsonrpc: '2.0', id: 'origin-1', method: 'tools/list' },
        headers: {
          'MCP-Protocol-Version' => '2025-11-25',
          'Origin' => 'https://untrusted.example'
        }
      )

      expect(response).to have_http_status(:forbidden)
      expect(response.parsed_body.dig('error', 'message')).to eq('Forbidden: Invalid Origin header')
    end

    it 'rejects requests for an unapproved website host' do
      post_mcp(
        { jsonrpc: '2.0', id: 'host-1', method: 'tools/list' },
        headers: {
          'Host' => 'untrusted.example',
          'MCP-Protocol-Version' => '2025-11-25'
        }
      )

      expect(response).to have_http_status(:forbidden)
      expect(response.parsed_body.dig('error', 'message')).to eq('Forbidden: Invalid Host header')
    end

    it 'rejects malformed and oversized JSON bodies' do
      post '/mcp',
           params: '{',
           headers: {
             'Content-Type' => 'application/json',
             'Accept' => 'application/json, text/event-stream'
           }

      expect(response).to have_http_status(:bad_request)
      expect(response.parsed_body.dig('error', 'message')).to eq('Parse error: Invalid JSON')

      post '/mcp',
           params: 'x' * ((4 * 1024 * 1024) + 1),
           headers: {
             'Content-Type' => 'application/json',
             'Accept' => 'application/json, text/event-stream'
           }

      expect(response).to have_http_status(:content_too_large)
      expect(response.parsed_body.dig('error', 'message')).to start_with('Payload too large')
    end
  end

  describe 'stateless transport methods' do
    it 'rejects GET streams and accepts idempotent DELETE cleanup' do
      get '/mcp', headers: { 'Accept' => 'text/event-stream' }

      expect(response).to have_http_status(:method_not_allowed)

      delete '/mcp', headers: { 'MCP-Protocol-Version' => '2025-11-25' }

      expect(response).to have_http_status(:ok)
      expect(response.parsed_body).to eq('success' => true)
    end
  end

  def collection_document(id)
    {
      'id' => id,
      '_root_' => id,
      'normalized_title_ssm' => [id.titleize],
      'level_ssm' => ['Collection'],
      'component_level_isim' => [0],
      'repository_ssim' => ['Manuscripts'],
      'has_online_content_ssim' => ['false']
    }
  end

  def advertised_output_schema(tool_name)
    post_mcp(
      { jsonrpc: '2.0', id: "#{tool_name}-schema", method: 'tools/list' },
      headers: { 'MCP-Protocol-Version' => '2025-11-25' }
    )

    response.parsed_body.dig('result', 'tools').find { |tool| tool.fetch('name') == tool_name }.fetch('outputSchema')
  end

  def solr_response(documents:, total:, next_cursor:)
    {
      'responseHeader' => { 'status' => 0, 'params' => {} },
      'response' => { 'numFound' => total, 'start' => 0, 'docs' => documents },
      'nextCursorMark' => next_cursor,
      'facet_counts' => { 'facet_fields' => {} }
    }
  end
end
