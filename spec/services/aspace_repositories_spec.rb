# frozen_string_literal: true

require 'rails_helper'

RSpec.describe AspaceRepositories do
  subject(:aspace_repository) { described_class.new }

  let(:client) { instance_double(AspaceClient, repositories:) }
  let(:repositories) do
    [{ 'repo_code' => 'ars', 'uri' => '/repositories/11', 'key' => 'value' },
     { 'repo_code' => 'sul', 'uri' => '/repositories/1', 'key' => 'value' }]
  end

  before do
    allow(AspaceClient).to receive(:new).with(aspace_config_set: :default).and_return(client)
    allow(Settings).to receive(:aspace).and_return(
      { default: Config::Options.new(harvestable_repository_codes: ['ars']) }
    )
  end

  describe '#all' do
    it 'returns array of all repositories from aspace' do
      expect(aspace_repository.all.count).to eq 2
    end

    it 'returns instances of Aspace::Repository' do
      expect(aspace_repository.all.first).to be_a Aspace::Repository
    end
  end

  describe '#all_harvestable' do
    it 'returns an array of all the harvestable repositories from aspace' do
      expect(aspace_repository.all_harvestable.count).to eq 1
    end
  end

  describe '#find_by' do
    it 'given an aspace repository code it returns the aspace id for the repository' do
      expect(aspace_repository.find_by(code: 'ars').id).to eq '11'
    end

    context 'when the repository code does not exist' do
      it 'returns nil' do
        expect(aspace_repository.find_by(code: 'code')).to be_nil
      end
    end
  end
end
