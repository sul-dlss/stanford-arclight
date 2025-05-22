# frozen_string_literal: true

require 'rails_helper'

RSpec.describe DeleteEadJob do
  let(:client) { instance_double(AspaceClient, all_published_resource_uris_by: ['/repositories/1/resources/2']) }
  let(:indexed_eads) do
    instance_double(DeleteEadJob::IndexedEads,
                    all: { '/repositories/1/resources/2' => 'ead123', '/repositories/1/resources/3' => 'ead456' })
  end
  let(:rsolr_client) { instance_double(RSolr::Client) }
  let(:repository) { instance_double(Blacklight::Solr::Repository, connection: rsolr_client) }

  before do
    allow(AspaceClient).to receive(:new).and_return(client)
    allow(DeleteEadJob::IndexedEads).to receive(:new).and_return(indexed_eads)
    allow(Blacklight).to receive(:default_index).and_return(repository)
    allow(rsolr_client).to receive(:commit)
    allow(rsolr_client).to receive(:delete_by_id)
  end

  it 'deletes any eads not published in ASpace' do
    described_class.perform_now(repository_id: 1, aspace_config_set: 'default')

    expect(DeleteEadJob::IndexedEads).to have_received(:new).with(repository_id: 1, aspace_config_set: 'default')
    expect(client).to have_received(:all_published_resource_uris_by).with(repository_id: 1)
    expect(rsolr_client).to have_received(:delete_by_id).with(['ead456'])
    expect(rsolr_client).to have_received(:commit)
  end

  # rubocop:disable RSpec/MultipleMemoizedHelpers
  describe '.enqueue_all' do
    let(:harvestable_repos) do
      [Aspace::Repository.new(repo_code: 'ars', uri: '/repositories/11', aspace_config_set: 'default'),
       Aspace::Repository.new(repo_code: 'eal', uri: '/repositories/4', aspace_config_set: 'default')]
    end
    let(:aspace_repository) do
      instance_double(AspaceRepositories, all_harvestable: harvestable_repos)
    end

    before do
      allow(AspaceRepositories).to receive(:new).and_return(aspace_repository)
    end

    it 'assembles and enqueues a job for each harvestable repository' do
      expect do
        described_class.enqueue_all
      end.to enqueue_job(described_class).exactly(2).times
      expect(aspace_repository).to have_received(:all_harvestable).exactly(1).time
    end
  end

  describe '#excessive_deletes_guard' do
    let(:ids_to_delete) { %w[ead123 ead456] }
    let(:override_excessive_deletes_guard) { false }

    it 'raises an error if the number of records to delete exceeds the limit' do
      allow(Settings).to receive(:max_automated_deletes).and_return(1)

      expect do
        described_class.new.excessive_deletes_guard(ids_to_delete:, override_excessive_deletes_guard:)
      end.to raise_error(DeleteEadJob::DeleteEadJobError, /Attempting to delete 2 records/)
    end

    it 'does not raise an error if the number of records to delete is within the limit' do
      allow(Settings).to receive(:max_automated_deletes).and_return(3)

      expect do
        described_class.new.excessive_deletes_guard(ids_to_delete:, override_excessive_deletes_guard:)
      end.not_to raise_error
    end

    it 'does not raise an error if override_excessive_deletes_guard is true' do
      allow(Settings).to receive(:max_automated_deletes).and_return(1)

      expect do
        described_class.new.excessive_deletes_guard(ids_to_delete:, override_excessive_deletes_guard: true)
      end.not_to raise_error
    end
  end
  # rubocop:enable RSpec/MultipleMemoizedHelpers
end
