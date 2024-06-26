# frozen_string_literal: true

require 'rails_helper'

RSpec.describe ArclightRepositoryMapper do
  describe '#map_to_code' do
    subject(:mapper) { described_class.new(aspace_repository_code:, file_identifier:) }

    let(:aspace_repository_code) { 'ars' }
    let(:file_identifier) { 'ars123.xml' }

    it 'returns the arclight repository code' do
      expect(mapper.map_to_code).to eq 'ars'
    end

    context 'when the aspace repository is speccoll' do
      let(:aspace_repository_code) { 'speccoll' }
      let(:file_identifier) { 'f1234.xml' }

      it 'uses the ead id to determine the arclight repository code' do
        expect(mapper.map_to_code).to eq 'uarc'
      end

      context 'when the ead id is uppercase' do
        let(:aspace_repository_code) { 'speccoll' }
        let(:file_identifier) { 'SCM1234.xml' }

        it 'uses the ead id to determine the arclight repository code' do
          expect(mapper.map_to_code).to eq 'uarc'
        end
      end

      context 'when the ead should be mapped to rarebooks' do
        let(:aspace_repository_code) { 'speccoll' }
        let(:file_identifier) { 'macweek.xml' }

        it 'uses the ead id to determine the arclight repository code' do
          expect(mapper.map_to_code).to eq 'rarebooks'
        end
      end
    end

    context 'when the supplied arguments cannot be mapped to an arclight repository' do
      let(:aspace_repository_code) { 'anarchive' }
      let(:file_identifier) { 'abc1234.xml' }

      it 'raises an error' do
        expect { mapper.map_to_code }.to raise_error ArclightRepositoryMapper::ArclightRepositoryMapperError
      end
    end
  end

  describe '.map_to_code' do
    subject(:mapper) { described_class.map_to_code(aspace_repository_code: 'ars', file_identifier: 'abs123.xml') }

    it 'returns the arclight repository code' do
      expect(mapper).to eq 'ars'
    end
  end
end
