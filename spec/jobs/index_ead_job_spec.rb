# frozen_string_literal: true

require 'rails_helper'

RSpec.describe IndexEadJob do
  let(:status) { double }

  before do
    allow(Open3).to receive(:capture2).and_return(['output', status])
    allow(status).to receive(:success?).and_return(true)
  end

  it 'sends a command to index the EAD in Solr with traject' do
    described_class.perform_now(file_path: 'data/sample.xml',
                                arclight_repository_code: 'ars',
                                resource_uri: '/repositories/2/resources/123',
                                solr_url: 'http://localhost/solr/core',
                                app_dir: '/some/directory')
    expect(Open3).to have_received(:capture2).with(
      { 'REPOSITORY_ID' => 'ars', 'RESOURCE_URI' => '/repositories/2/resources/123' },
      ['bundle',
       'exec',
       'traject',
       '-u',
       'http://localhost/solr/core',
       '-i',
       'xml',
       '-c',
       './lib/traject/sul_config.rb',
       'data/sample.xml'].join(' '),
      { chdir: '/some/directory' }
    )
  end

  context 'when the arclight repository code is not provided as an argument' do
    it 'infers the repository code from the file path' do
      described_class.perform_now(file_path: '/data/archive/sample.xml',
                                  resource_uri: '/repositories/2/resources/123',
                                  solr_url: 'http://localhost/solr/core',
                                  app_dir: '/some/directory')

      expect(Open3).to have_received(:capture2).with({ 'REPOSITORY_ID' => 'archive',
                                                       'RESOURCE_URI' => '/repositories/2/resources/123' },
                                                     anything, anything)
    end
  end

  context 'when the traject command does not succeed' do
    before do
      allow(status).to receive(:success?).and_return(false)
    end

    it 'raises an error' do
      expect do
        described_class.perform_now(file_path: 'data/sample.xml',
                                    arclight_repository_code: 'ars',
                                    resource_uri: '/repositories/2/resources/123',
                                    solr_url: 'http://localhost/solr/core',
                                    app_dir: '/some/directory')
      end.to raise_error(IndexEadJob::IndexEadError)
    end
  end
end
