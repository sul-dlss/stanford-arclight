# frozen_string_literal: true

require 'rails_helper'

RSpec.describe DeleteSafeguard do
  subject(:safeguard) { described_class.check(delete_count:, index_count:) }

  describe '.check' do
    context 'when delete count exceeds maximum allowed' do
      let(:delete_count) { 101 }
      let(:index_count) { 200 }

      it 'raises a DeleteSafeguardError' do
        expect { safeguard }.to raise_error(DeleteSafeguard::DeleteSafeguardError, /exceeds the limit of 100/)
      end
    end

    context 'when the delete count is less than the maximum allowed' do
      let(:delete_count) { 50 }
      let(:index_count) { 200 }

      it 'does not raise an error' do
        expect { safeguard }.not_to raise_error
      end
    end

    context 'when delete count matches the index count' do
      let(:delete_count) { 50 }
      let(:index_count) { 50 }

      it 'raises a DeleteSafeguardError' do
        expect { safeguard }.to raise_error(DeleteSafeguard::DeleteSafeguardError, /would remove all 50 records/)
      end
    end
  end
end
