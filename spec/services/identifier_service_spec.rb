# frozen_string_literal: true

require 'rails_helper'

RSpec.describe IdentifierService do
  subject(:identifier_service) { described_class.new(identifiers).to_s }

  let(:identifiers) { ['ars-1234.xml'] }

  describe '.to_s' do
    it 'returns a normalized identifier string' do
      expect(identifier_service).to eq('ars-1234')
    end

    context 'when the first identifier is nil' do
      let(:identifiers) { [nil, 'Université de Toulouse'] }

      it 'returns a normalized identifier string from the second identifier' do
        expect(identifier_service).to eq('universite-de-toulouse')
      end
    end

    context 'when no valid identifiers can be formed' do
      let(:identifiers) { ['', nil] }

      it 'raises an IDNotFound exception' do
        expect { identifier_service }.to raise_error(Arclight::Exceptions::IDNotFound)
      end
    end
  end
end
