# frozen_string_literal: true

require 'rails_helper'

RSpec.describe DownloadEadJob do
  let(:client) { instance_double(AspaceClient, resource_description: '<a/>') }
  let(:file) { instance_double(File, puts: true) }
  let(:harvestable_repos) do
    [Aspace::Repository.new(repo_code: 'ars', uri: '/repositories/11'),
     Aspace::Repository.new(repo_code: 'eal', uri: '/repositories/4')]
  end
  let(:aspace_repository) do
    instance_double(AspaceRepositories, all_harvestable: harvestable_repos)
  end

  before do
    allow(AspaceClient).to receive(:new).and_return(client)
    allow(File).to receive(:open).and_yield(file)
    allow(FileUtils).to receive(:mkdir_p)
    allow(AspaceRepositories).to receive(:new).and_return(aspace_repository)
  end

  it 'fetches an EAD from the client service' do
    described_class.perform_now(resource_uri: '/repositories/1/resources/123', file_name: 'abc123',
                                data_dir: '/data/archive/')

    expect(client).to have_received(:resource_description).with('/repositories/1/resources/123')
  end

  it 'writes the formatted EAD XML to a file' do
    described_class.perform_now(resource_uri: '/repositories/1/resources/123', file_name: 'abc123',
                                data_dir: '/data/archive/')

    expect(file).to have_received(:puts).with("<?xml version=\"1.0\"?>\n<a/>\n")
  end

  it 'cleans up the supplied file name' do
    described_class.perform_now(resource_uri: '/repositories/1/resources/123', file_name: 'abc 123/ABC.XML',
                                data_dir: '/data/archive/')

    expect(File).to have_received(:open).with('/data/archive/abc-123-abc.xml', 'wb')
  end

  context 'when index param value is true' do
    it 'enqueues an indexing job with the EAD file' do
      expect do
        described_class.perform_now(resource_uri: '/repositories/1/resources/123', file_name: 'abc123',
                                    data_dir: '/data/archive/', index: true)
      end.to enqueue_job(IndexEadJob).once.with(file_path: '/data/archive/abc123.xml',
                                                resource_uri: '/repositories/1/resources/123')
    end
  end

  context 'when generate_pdf param value is true' do
    it 'enqueues a generate pdf job for the EAD file' do
      expect do
        described_class.perform_now(resource_uri: '/repositories/1/resources/123', file_name: 'abc123',
                                    data_dir: '/data/archive/', generate_pdf: true)
      end.to enqueue_job(GeneratePdfJob).once.with(file_path: '/data/archive/abc123.xml', file_name: 'abc123',
                                                   data_dir: '/data/archive/')
    end
  end

  describe '.enqueue_all' do
    before do
      allow(client).to receive(:published_resource_uris).with(repository_id: '11',
                                                              updated_after: nil)
                                                        .and_return([{ 'uri' => '/repositories/11/resources/1',
                                                                       'ead_id' => 'ars123' },
                                                                     { 'uri' => '/repositories/11/resources/2',
                                                                       'ead_id' => 'ars456' }])
      allow(client).to receive(:published_resource_uris).with(repository_id: '4',
                                                              updated_after: nil)
                                                        .and_return([{ 'uri' => '/repositories/4/resources/1',
                                                                       'ead_id' => 'eal123' },
                                                                     { 'uri' => '/repositories/4/resources/2',
                                                                       'ead_id' => 'eal456' }])
    end

    it "assembles and enqueues a job for each repository's resource uri" do
      expect do
        described_class.enqueue_all
      end.to enqueue_job(described_class).exactly(4).times
      expect(client).to have_received(:published_resource_uris).exactly(2).times
      expect(FileUtils).to have_received(:mkdir_p).exactly(5).times
      expect(aspace_repository).to have_received(:all_harvestable).exactly(1).time
    end
  end

  describe '.enqueue_all_updated' do
    before do
      allow(client).to receive(:published_resource_uris).with(
        repository_id: '11', updated_after: '2023-12-12'
      ).and_return(
        [{ 'uri' => '/repositories/11/resources/1', 'ead_id' => 'ars123' },
         { 'uri' => '/repositories/11/resources/2', 'ead_id' => 'ars456' }]
      )
      allow(client).to receive(:published_resource_with_updated_component_uris).with(
        repository_id: '11', updated_after: '2023-12-12',
        uris_to_exclude: ['/repositories/11/resources/1', '/repositories/11/resources/2']
      ).and_return(
        [{ 'uri' => '/repositories/11/resources/3', 'ead_id' => 'ars789' }]
      )
      allow(client).to receive(:published_resource_uris).with(
        repository_id: '4', updated_after: '2023-12-12'
      ).and_return(
        [{ 'uri' => '/repositories/4/resources/1', 'ead_id' => 'eal123' },
         { 'uri' => '/repositories/4/resources/2', 'ead_id' => 'eal456' }]
      )
      allow(client).to receive(:published_resource_with_updated_component_uris).with(
        repository_id: '4', updated_after: '2023-12-12',
        uris_to_exclude: ['/repositories/4/resources/1', '/repositories/4/resources/2']
      ).and_return(
        [{ 'uri' => '/repositories/4/resources/3', 'ead_id' => 'eal789' }]
      )
    end

    it 'fetches all resource uris from aspace limited to a specified date' do
      described_class.enqueue_all_updated(updated_after: '2023-12-12')
      expect(client).to have_received(:published_resource_uris).with(repository_id: '11', updated_after: '2023-12-12')
      expect(client).to have_received(:published_resource_with_updated_component_uris).with(
        repository_id: '11',
        updated_after: '2023-12-12',
        uris_to_exclude: ['/repositories/11/resources/1', '/repositories/11/resources/2']
      )
      expect(client).to have_received(:published_resource_uris).with(repository_id: '4', updated_after: '2023-12-12')
      expect(client).to have_received(:published_resource_with_updated_component_uris).with(
        repository_id: '4',
        updated_after: '2023-12-12',
        uris_to_exclude: ['/repositories/4/resources/1', '/repositories/4/resources/2']
      )
    end
  end

  describe '.enqueue_one_by' do
    before do
      allow(aspace_repository).to receive(:find_by).with({ code: 'ars' }).and_return(
        Aspace::Repository.new(repo_code: 'ars', uri: '/repositories/11')
      )
      allow(client).to receive(:published_resource_uris).and_return([{ 'uri' => '/repositories/11/resources/1',
                                                                       'ead_id' => 'ars123' },
                                                                     { 'uri' => '/repositories/11/resources/2',
                                                                       'ead_id' => 'ars456' }])
    end

    it 'enqueues two jobs with the repository of interest' do
      expect do
        described_class.enqueue_one_by(aspace_repository_code: 'ars')
      end.to enqueue_job(described_class).exactly(2).times
    end
  end
end
