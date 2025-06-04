# frozen_string_literal: true

require 'rails_helper'

RSpec.describe DownloadEadJob do
  let(:client) { instance_double(AspaceClient, resource_description: '<a/>') }
  let(:file) { instance_double(File, puts: true) }
  let(:harvestable_repos) do
    [Aspace::Repository.new(repo_code: 'ars', uri: '/repositories/11', aspace_config_set: 'default'),
     Aspace::Repository.new(repo_code: 'eal', uri: '/repositories/4', aspace_config_set: 'default')]
  end
  let(:aspace_repository) do
    instance_double(AspaceRepositories, all_harvestable: harvestable_repos)
  end
  let(:arclight_repositories) do
    [Arclight::Repository.new(slug: 'ars'),
     Arclight::Repository.new(slug: 'eal')]
  end

  before do
    allow(AspaceClient).to receive(:new).and_return(client)
    allow(File).to receive(:open).and_yield(file)
    allow(FileUtils).to receive(:mkdir_p)
    allow(AspaceRepositories).to receive(:new).and_return(aspace_repository)
    allow(Arclight::Repository).to receive(:all).and_return(arclight_repositories)
  end

  it 'fetches an EAD from the client service' do
    described_class.perform_now(resource_uri: '/repositories/1/resources/123', aspace_config_set: 'default',
                                file_name: 'abc123', file_dir: '/data/archive/', index: false, generate_pdf: false)

    expect(client).to have_received(:resource_description).with('/repositories/1/resources/123')
  end

  it 'writes the formatted EAD XML to a file' do
    described_class.perform_now(resource_uri: '/repositories/1/resources/123', aspace_config_set: 'default',
                                file_name: 'abc123', file_dir: '/data/archive/', index: false, generate_pdf: false)

    expect(file).to have_received(:puts).with("<?xml version=\"1.0\"?>\n<a/>\n")
  end

  context 'when index param value is true' do
    it 'enqueues an indexing job with the EAD file' do
      expect do
        described_class.perform_now(resource_uri: '/repositories/1/resources/123', aspace_config_set: 'default',
                                    file_name: 'abc123', file_dir: '/data/archive/', index: true, generate_pdf: false)
      end.to enqueue_job(IndexEadJob).once.with(file_path: '/data/archive/abc123.xml')
    end
  end

  context 'when generate_pdf param value is true' do
    it 'enqueues a generate pdf job for the EAD file' do
      expect do
        described_class.perform_now(resource_uri: '/repositories/1/resources/123', aspace_config_set: 'default',
                                    file_name: 'abc123', file_dir: '/data/archive/', index: false, generate_pdf: true)
      end.to enqueue_job(GeneratePdfJob).once.with(file_path: '/data/archive/abc123.xml', file_name: 'abc123',
                                                   data_dir: '/data/archive/', skip_existing: false)
    end
  end

  describe '.enqueue_all' do
    before do
      allow(Honeybadger).to receive(:notify)
      allow(client).to receive(:published_resources).with(repository_id: '11', updated_after: nil)
                                                    .and_return([
                                                                  { 'uri' => '/repositories/11/resources/1',
                                                                    'ead_id' => 'ars123' },
                                                                  { 'uri' => '/repositories/11/resources/2',
                                                                    'identifier' => 'ars456' },
                                                                  # This resource will not be enqueued
                                                                  # because it has no ead_id or identifier
                                                                  { 'uri' => '/repositories/11/resources/23' }
                                                                ])
      allow(client).to receive(:published_resources).with(repository_id: '4', updated_after: nil)
                                                    .and_return([
                                                                  { 'uri' => '/repositories/4/resources/1',
                                                                    'ead_id' => 'eal123' },

                                                                  { 'uri' => '/repositories/4/resources/2',
                                                                    'identifier' => 'eal456' }
                                                                ])
    end

    it "assembles and enqueues a job for each repository's resource uri" do
      # One of the 5 resources above will not be enqueued because it has no ead_id or identifier
      # Expect 4 jobs to be enqueued
      expect do
        described_class.enqueue_all
      end.to enqueue_job(described_class).exactly(4).times
      expect(client).to have_received(:published_resources).exactly(2).times
      expect(FileUtils).to have_received(:mkdir_p).exactly(2).times
      expect(aspace_repository).to have_received(:all_harvestable).exactly(1).time

      # Expect the resource with no ead_id or identifier to trigger a notification
      expect(Honeybadger).to have_received(:notify).with('Failed to create filename for /repositories/11/resources/23: Resources from ArchivesSpace must have an EAD ID or identifier') # rubocop:disable Layout/LineLength
    end
  end

  describe '.enqueue_all_updated' do
    before do
      allow(client).to receive(:published_resources).with(
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
      allow(client).to receive(:published_resource_with_linked_agent_uris).with(
        repository_id: '11', updated_after: '2023-12-12',
        uris_to_exclude: ['/repositories/11/resources/1', '/repositories/11/resources/2']
      ).and_return(
        [{ 'uri' => '/repositories/11/resources/4', 'ead_id' => 'ars000' }]
      )
      allow(client).to receive(:published_resources).with(
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
      allow(client).to receive(:published_resource_with_linked_agent_uris).with(
        repository_id: '4', updated_after: '2023-12-12',
        uris_to_exclude: ['/repositories/4/resources/1', '/repositories/4/resources/2']
      ).and_return(
        [{ 'uri' => '/repositories/4/resources/4', 'ead_id' => 'eal000' }]
      )
    end

    it 'fetches all resource uris from aspace limited to a specified date' do
      described_class.enqueue_all_updated(updated_after: '2023-12-12')
      expect(client).to have_received(:published_resources).with(repository_id: '11', updated_after: '2023-12-12')
      expect(client).to have_received(:published_resource_with_updated_component_uris).with(
        repository_id: '11',
        updated_after: '2023-12-12',
        uris_to_exclude: ['/repositories/11/resources/1', '/repositories/11/resources/2']
      )
      expect(client).to have_received(:published_resource_with_linked_agent_uris).with(
        repository_id: '11',
        updated_after: '2023-12-12',
        uris_to_exclude: ['/repositories/11/resources/1', '/repositories/11/resources/2']
      )
      expect(client).to have_received(:published_resources).with(repository_id: '4', updated_after: '2023-12-12')
      expect(client).to have_received(:published_resource_with_updated_component_uris).with(
        repository_id: '4',
        updated_after: '2023-12-12',
        uris_to_exclude: ['/repositories/4/resources/1', '/repositories/4/resources/2']
      )
      expect(client).to have_received(:published_resource_with_linked_agent_uris).with(
        repository_id: '4',
        updated_after: '2023-12-12',
        uris_to_exclude: ['/repositories/4/resources/1', '/repositories/4/resources/2']
      )
    end
  end

  describe '.enqueue_one_by' do
    before do
      allow(aspace_repository).to receive(:find_by).with({ code: 'ars', aspace_config_set: :default }).and_return(
        Aspace::Repository.new(repo_code: 'ars', uri: '/repositories/11', aspace_config_set: 'default')
      )
      allow(client).to receive(:published_resources).and_return([{ 'uri' => '/repositories/11/resources/1',
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
