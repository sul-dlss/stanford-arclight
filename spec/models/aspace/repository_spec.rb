# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Aspace::Repository do
  subject(:repository) do
    described_class.new(repo_code: 'ARS', uri: '/repositories/11', aspace_config_set: 'default')
  end

  let(:client) do
    instance_double(AspaceClient)
  end

  before do
    allow(AspaceClient).to receive(:new).with(aspace_config_set: 'default').and_return(client)
  end

  it { expect(repository.id).to eq '11' }
  it { expect(repository.code).to eq 'ars' }
  it { expect(repository.uri).to eq '/repositories/11' }
  it { expect(repository.harvestable?).to be true }
  it { expect(repository.aspace_config_set).to eq 'default' }

  describe '#each_published_resource' do
    before do
      allow(client).to(receive(:published_resource_uris))
                   .with(repository_id: '11', updated_after: nil)
                   .and_return([{ ead_id: 'ARS123', uri: '/repositories/11/resources/12' }])
    end

    it 'returns instances of Aspace::Resource' do
      expect(repository.each_published_resource.to_a.size).to eq 1
      expect(repository.each_published_resource.to_a.first).to be_a Aspace::Resource
    end
  end

  describe '#each_published_resource_with_updated_components' do
    before do
      allow(client).to(receive(:published_resource_with_updated_component_uris))
                   .with(repository_id: '11', updated_after: '2024-05-09', uris_to_exclude: nil)
                   .and_return([{ ead_id: 'ARS123', uri: '/repositories/11/resources/12' }])
    end

    it 'returns instances of Aspace::Resource' do
      expect(repository.each_published_resource_with_updated_components(updated_after: '2024-05-09')
                       .to_a.size).to eq 1
      expect(repository.each_published_resource_with_updated_components(updated_after: '2024-05-09')
                       .to_a.first).to be_a Aspace::Resource
    end
  end

  describe '#each_published_resource_with_updated_agents' do
    before do
      allow(client).to(receive(:published_resource_with_linked_agent_uris))
                   .with(repository_id: '11', updated_after: '2024-05-09', uris_to_exclude: nil)
                   .and_return([{ ead_id: 'ARS123', uri: '/repositories/11/resources/12' }])
    end

    it 'returns instances of Aspace::Resource' do
      expect(repository.each_published_resource_with_updated_agents(updated_after: '2024-05-09')
                      .to_a.size).to eq 1
      expect(repository.each_published_resource_with_updated_agents(updated_after: '2024-05-09')
                      .to_a.first).to be_a Aspace::Resource
    end
  end
end
