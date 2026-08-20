# frozen_string_literal: true

require 'rails_helper'

RSpec.describe StanfordArclightMcp::ArchivalRecord do
  it 'projects every populated display field into a semantic content inventory' do
    document = SolrDocument.new(
      'id' => 'collection',
      '_root_' => 'collection',
      'normalized_title_ssm' => ['Example papers'],
      'level_ssm' => ['Collection'],
      'component_level_isim' => [0],
      'repository_ssm' => ['Unconfigured Repository'],
      'abstract_html_tesm' => ['<p>A short <em>overview</em>.</p>'],
      'scopecontent_html_tesm' => ['<p>Correspondence &amp; research files.</p>'],
      'acqinfo_ssim' => ['Gift of the creator.'],
      'physdesc_tesim' => ['12 manuscript boxes'],
      'relatedmaterial_html_tesm' => ['<p>See also the Example photographs.</p>'],
      'prefercite_html_tesm' => ['<p>Example papers, Stanford Libraries.</p>'],
      'access_subjects_ssim' => ['Computer science'],
      'names_coll_ssim' => ['Example, Jane'],
      'has_online_content_ssim' => ['false']
    )
    controller = McpController.new
    allow(controller).to receive(:solr_document_url).and_return('https://archives.example/catalog/collection')

    record = described_class.new(document:, controller:).to_h.fetch(:record)

    expect(record.fetch(:content_inventory)).to eq(
      [
        { section: 'description', field: 'abstract', label: 'Abstract', value_count: 1, character_count: 17 },
        {
          section: 'description', field: 'scope_and_contents', label: 'Scope and Contents', value_count: 1,
          character_count: 32
        },
        {
          section: 'physical_description', field: 'physical_description', label: 'Physical Description',
          value_count: 1, character_count: 19
        },
        {
          section: 'administrative', field: 'acquisition_information', label: 'Acquisition Information',
          value_count: 1, character_count: 20
        },
        {
          section: 'related_materials', field: 'related_materials', label: 'Related Materials', value_count: 1,
          character_count: 33
        },
        {
          section: 'citation', field: 'preferred_citation', label: 'Preferred Citation', value_count: 1,
          character_count: 35
        },
        {
          section: 'indexed_terms', field: 'subjects', label: 'Subjects', value_count: 1,
          character_count: 16
        },
        {
          section: 'indexed_terms', field: 'names', label: 'Names', value_count: 1, character_count: 13
        }
      ]
    )
    expect(record.fetch(:content)).to include(
      {
        section: 'description', field: 'abstract', label: 'Abstract', value_index: 0,
        text: 'A short overview.', range: { start: 0, end: 17, total: 17 }
      },
      {
        section: 'administrative', field: 'acquisition_information', label: 'Acquisition Information',
        value_index: 0, text: 'Gift of the creator.', range: { start: 0, end: 20, total: 20 }
      },
      {
        section: 'citation', field: 'preferred_citation', label: 'Preferred Citation', value_index: 0,
        text: 'Example papers, Stanford Libraries.', range: { start: 0, end: 35, total: 35 }
      }
    )
    expect(record).to include(complete: true)
    expect(record).not_to include(:next_cursor, :extent, :languages, :notes)
  end

  it 'continues oversized descriptive values without silently truncating them' do
    document = SolrDocument.new(
      'id' => 'large-record',
      '_root_' => 'large-record',
      'normalized_title_ssm' => ['Large record'],
      'level_ssm' => ['Collection'],
      'component_level_isim' => [0],
      'repository_ssm' => ['Unconfigured Repository'],
      'scopecontent_html_tesm' => ['abcdefghij'],
      'has_online_content_ssim' => ['false']
    )
    controller = McpController.new
    allow(controller).to receive(:solr_document_url).and_return('https://archives.example/catalog/large-record')

    first = described_class.new(document:, controller:, max_content_characters: 6).to_h.fetch(:record)
    second = described_class.new(
      document:, controller:, max_content_characters: 6, cursor: first.fetch(:next_cursor)
    ).to_h.fetch(:record)

    expect(first).to include(
      complete: false,
      content_inventory: [
        {
          section: 'description', field: 'scope_and_contents', label: 'Scope and Contents', value_count: 1,
          character_count: 10
        }
      ],
      content: [
        {
          section: 'description', field: 'scope_and_contents', label: 'Scope and Contents', value_index: 0,
          text: 'abcdef', range: { start: 0, end: 6, total: 10 }
        }
      ]
    )
    expect(first.fetch(:next_cursor)).to be_present
    expect(second).to include(
      complete: true,
      content: [
        {
          section: 'description', field: 'scope_and_contents', label: 'Scope and Contents', value_index: 0,
          text: 'ghij', range: { start: 6, end: 10, total: 10 }
        }
      ]
    )
    expect(second).not_to include(:next_cursor)
    expect(first.dig(:content, 0, :text) + second.dig(:content, 0, :text)).to eq('abcdefghij')
  end

  it 'rejects a continuation cursor after the indexed descriptive content changes' do
    attributes = {
      'id' => 'changing-record',
      '_root_' => 'changing-record',
      'normalized_title_ssm' => ['Changing record'],
      'level_ssm' => ['Collection'],
      'component_level_isim' => [0],
      'repository_ssm' => ['Unconfigured Repository'],
      'scopecontent_html_tesm' => ['abcdefghij'],
      'has_online_content_ssim' => ['false']
    }
    controller = McpController.new
    allow(controller).to receive(:solr_document_url).and_return('https://archives.example/catalog/changing-record')
    first = described_class.new(
      document: SolrDocument.new(attributes), controller:, max_content_characters: 6
    ).to_h.fetch(:record)
    changed_document = SolrDocument.new(attributes.merge('scopecontent_html_tesm' => ['changed text']))

    expect do
      described_class.new(
        document: changed_document, controller:, cursor: first.fetch(:next_cursor), max_content_characters: 6
      ).to_h
    end.to raise_error(StanfordArclightMcp::ArchivalRecordContent::InvalidCursor)
  end

  it 'attributes direct and ancestor access information to its source records' do
    document = SolrDocument.new(
      'id' => 'collection_series_folder',
      '_root_' => 'collection',
      'normalized_title_ssm' => ['Correspondence'],
      'level_ssm' => ['Folder'],
      'component_level_isim' => [2],
      'parent_ids_ssim' => %w[collection collection_series],
      'parent_unittitles_ssm' => ['Example papers', 'Series 1'],
      'parent_levels_ssm' => %w[Collection Series],
      'repository_ssm' => ['Unconfigured Repository'],
      'accessrestrict_html_tesm' => ['<p>Fragile originals require staff approval.</p>'],
      'parent_access_restrict_tesm' => ['<p>Collection is closed until 2035.</p>'],
      'parent_access_restrict_source_id_ssi' => 'collection',
      'parent_access_restrict_source_title_ssi' => 'Example papers',
      'parent_access_restrict_source_level_ssi' => 'Collection',
      'parent_access_terms_tesm' => ['<p>Copyright retained by the creator.</p>'],
      'parent_access_terms_source_id_ssi' => 'collection_series',
      'parent_access_terms_source_title_ssi' => 'Series 1',
      'parent_access_terms_source_level_ssi' => 'Series',
      'has_online_content_ssim' => ['false']
    )
    controller = McpController.new
    allow(controller).to receive(:solr_document_url) do |id|
      "https://archives.example/catalog/#{id}"
    end

    record = described_class.new(document:, controller:).to_h.fetch(:record)

    expect(record.fetch(:access)).to eq(
      status: 'complete',
      restrictions: [
        {
          source: {
            id: 'collection_series_folder',
            url: 'https://archives.example/catalog/collection_series_folder',
            title: 'Correspondence',
            level: 'Folder'
          },
          values: ['Fragile originals require staff approval.']
        },
        {
          source: {
            id: 'collection',
            url: 'https://archives.example/catalog/collection',
            title: 'Example papers',
            level: 'Collection'
          },
          values: ['Collection is closed until 2035.']
        }
      ],
      use_restrictions: [
        {
          source: {
            id: 'collection_series',
            url: 'https://archives.example/catalog/collection_series',
            title: 'Series 1',
            level: 'Series'
          },
          values: ['Copyright retained by the creator.']
        }
      ]
    )
    expect(record.fetch(:content_inventory).pluck(:field)).not_to include('access_restrictions', 'use_restrictions')
  end

  it 'attributes inherited access from ancestor documents when the index has no provenance fields' do
    document = SolrDocument.new(
      'id' => 'collection_series_folder',
      '_root_' => 'collection',
      'normalized_title_ssm' => ['Correspondence'],
      'level_ssm' => ['Folder'],
      'component_level_isim' => [2],
      'parent_ids_ssim' => %w[collection collection_series],
      'parent_unittitles_ssm' => ['Example papers', 'Series 1'],
      'parent_levels_ssm' => %w[Collection Series],
      'repository_ssm' => ['Unconfigured Repository'],
      'parent_access_restrict_tesm' => ['Series is closed until 2035.'],
      'parent_access_terms_tesm' => ['Copyright retained by the creator.'],
      'has_online_content_ssim' => ['false']
    )
    ancestors = [
      SolrDocument.new(
        'id' => 'collection',
        'normalized_title_ssm' => ['Example papers'],
        'level_ssm' => ['Collection'],
        'accessrestrict_html_tesm' => ['Collection restriction.']
      ),
      SolrDocument.new(
        'id' => 'collection_series',
        'normalized_title_ssm' => ['Series 1'],
        'level_ssm' => ['Series'],
        'accessrestrict_html_tesm' => ['Series is closed until 2035.'],
        'userestrict_html_tesm' => ['Copyright retained by the creator.']
      )
    ]
    controller = McpController.new
    allow(controller).to receive(:solr_document_url) do |id|
      "https://archives.example/catalog/#{id}"
    end

    record = described_class.new(document:, controller:, ancestor_documents: ancestors).to_h.fetch(:record)

    expect(record.fetch(:access)).to eq(
      status: 'complete',
      restrictions: [
        {
          source: {
            id: 'collection_series',
            url: 'https://archives.example/catalog/collection_series',
            title: 'Series 1',
            level: 'Series'
          },
          values: ['Series is closed until 2035.']
        }
      ],
      use_restrictions: [
        {
          source: {
            id: 'collection_series',
            url: 'https://archives.example/catalog/collection_series',
            title: 'Series 1',
            level: 'Series'
          },
          values: ['Copyright retained by the creator.']
        }
      ]
    )
  end

  it 'reports incomplete access provenance instead of treating unattributed inherited text as absent' do
    document = SolrDocument.new(
      'id' => 'component',
      '_root_' => 'collection',
      'normalized_title_ssm' => ['Component'],
      'level_ssm' => ['File'],
      'component_level_isim' => [1],
      'parent_ids_ssim' => ['collection'],
      'parent_unittitles_ssm' => ['Example papers'],
      'parent_levels_ssm' => ['Collection'],
      'repository_ssm' => ['Unconfigured Repository'],
      'parent_access_restrict_tesm' => ['Closed until 2035.'],
      'has_online_content_ssim' => ['false']
    )
    controller = McpController.new
    allow(controller).to receive(:solr_document_url).and_return('https://archives.example/catalog/component')

    access = described_class.new(document:, controller:).to_h.dig(:record, :access)

    expect(access).to eq(status: 'incomplete', restrictions: [], use_restrictions: [])
  end

  it 'does not attribute inherited access when the ancestor text does not match' do
    document = SolrDocument.new(
      'id' => 'component',
      '_root_' => 'collection',
      'normalized_title_ssm' => ['Component'],
      'level_ssm' => ['File'],
      'component_level_isim' => [1],
      'parent_ids_ssim' => ['collection'],
      'parent_unittitles_ssm' => ['Example papers'],
      'parent_levels_ssm' => ['Collection'],
      'repository_ssm' => ['Unconfigured Repository'],
      'parent_access_restrict_tesm' => ['Closed until 2035.'],
      'parent_access_restrict_source_id_ssi' => 'collection',
      'has_online_content_ssim' => ['false']
    )
    ancestor = SolrDocument.new(
      'id' => 'collection',
      'normalized_title_ssm' => ['Example papers'],
      'level_ssm' => ['Collection'],
      'accessrestrict_html_tesm' => ['Open for research.']
    )
    controller = McpController.new
    allow(controller).to receive(:solr_document_url).and_return('https://archives.example/catalog/component')

    access = described_class.new(document:, controller:, ancestor_documents: [ancestor]).to_h.dig(:record, :access)

    expect(described_class.requires_ancestor_lookup?(document)).to be(true)
    expect(access).to eq(status: 'incomplete', restrictions: [], use_restrictions: [])
  end

  it 'returns false when repository request configuration is unavailable' do
    document = SolrDocument.new(
      'id' => 'cubberley-test',
      '_root_' => 'cubberley-test',
      'normalized_title_ssm' => ['Test collection'],
      'level_ssm' => ['Collection'],
      'component_level_isim' => [0],
      'repository_ssm' => ['Unconfigured Repository'],
      'has_online_content_ssim' => ['false']
    )
    controller = McpController.new
    allow(controller).to receive(:solr_document_url).and_return('https://archives.example/catalog/cubberley-test')

    record = described_class.new(document:, controller:).to_h.fetch(:record)

    expect(record.fetch(:repository)).to include(requestable: false)
  end
end
