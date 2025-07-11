# frozen_string_literal: true

require 'rails_helper'

RSpec.describe DeleteEadJob do
  let(:client) do
    instance_double(AspaceClient,
                    all_published_resource_arks_by: ['ark:/22236/c88366e7e5-b138-4d4f-b210-9063f159547c'])
  end
  let(:indexed_eads) do
    instance_double(SolrPaginatedQuery,
                    all: { 'ark:/22236/c88366e7e5-b138-4d4f-b210-9063f159547c' => 'ead123',
                           'ark:/22236/c83390a9ec-7afc-45ef-a2d1-0b065b53591d' => 'ead456' })
  end
  let(:rsolr_client) { instance_double(RSolr::Client) }
  let(:repository) { instance_double(Blacklight::Solr::Repository, connection: rsolr_client) }

  before do
    allow(AspaceClient).to receive(:new).and_return(client)
    allow(SolrPaginatedQuery).to receive(:new).and_return(indexed_eads)
    allow(Blacklight).to receive(:default_index).and_return(repository)
    allow(rsolr_client).to receive(:commit)
    allow(rsolr_client).to receive(:delete_by_id)
    allow(DeleteSafeguard).to receive(:check).and_return(nil)
  end

  it 'deletes any eads not published in ASpace' do
    described_class.perform_now(repository_id: 1, aspace_config_set: 'default', ark_shoulder: 'c8')

    expect(SolrPaginatedQuery).to(
      have_received(:new).with({ fields_to_return: %w[sul_ark_id_ssi id],
                                 filter_queries: { sul_ark_shoulder_ssi: 'c8' } })
    )
    expect(client).to have_received(:all_published_resource_arks_by).with(repository_id: 1)
    expect(rsolr_client).to have_received(:delete_by_id).with(['ead456'])
    expect(rsolr_client).to have_received(:commit)
  end

  # rubocop:disable RSpec/MultipleMemoizedHelpers
  describe '.enqueue_all' do
    let(:harvestable_repos) do
      [Aspace::Repository.new(repo_code: 'ars', uri: '/repositories/11',
                              aspace_config_set: 'default', ark_shoulder: 'c8'),
       Aspace::Repository.new(repo_code: 'eal', uri: '/repositories/4',
                              aspace_config_set: 'default', ark_shoulder: 'r2')]
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

    context 'when delete safeguard raises an error' do
      before do
        allow(DeleteSafeguard).to receive(:check).and_raise(DeleteSafeguard::DeleteSafeguardError)
      end

      it 'raises an error when the delete safeguard is triggered' do
        expect do
          described_class.perform_now(repository_id: 1, ark_shoulder: 's1', aspace_config_set: 'default')
        end.to raise_error(DeleteSafeguard::DeleteSafeguardError)
      end
    end

    context 'when delete safeguard is skipped' do
      it 'raises an error when the delete safeguard is triggered' do
        expect do
          described_class.perform_now(repository_id: 1, ark_shoulder: 's1',
                                      aspace_config_set: 'default', skip_delete_safeguard: true)
        end.not_to raise_error(DeleteSafeguard::DeleteSafeguardError)
      end
    end
  end
  # rubocop:enable RSpec/MultipleMemoizedHelpers
end
