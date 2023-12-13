# frozen_string_literal: true

require 'rails_helper'

RSpec.describe AspaceRepository do
  subject(:aspace_repository) { described_class.new }

  let(:client) { instance_double(AspaceClient, repositories:) }
  let(:repositories) do
    [{ 'repo_code' => 'ars', 'uri' => '/repositories/11', 'key' => 'value' },
     { 'repo_code' => 'sul', 'uri' => '/repositories/1', 'key' => 'value' }]
  end

  before do
    allow(AspaceClient).to receive(:new).and_return(client)
  end

  describe '#all' do
    it 'returns array of all repositories from aspace' do
      expect(aspace_repository.all).to eq({ 'ars' => '11', 'sul' => '1' })
    end
  end

  describe '#all_harvestable' do
    it 'returns an array of all the harvestable repositories from aspace' do
      expect(aspace_repository.all_harvestable).to eq({ 'ars' => '11' })
    end
  end

  describe '#find_by' do
    it 'given an aspace repository code it returns the aspace id for the repository' do
      expect(aspace_repository.find_by(code: 'ars')).to eq '11'
    end

    context 'when the repository code does not exist' do
      it 'returns nil' do
        expect(aspace_repository.find_by(code: 'code')).to be_nil
      end
    end
  end
end
