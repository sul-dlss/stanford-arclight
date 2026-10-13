# frozen_string_literal: true

require 'rails_helper'

RSpec.describe AspaceRepositorySync do
  let(:repository) do
    instance_double(Aspace::Repository, aspace_config_set: 'default', code: 'ars')
  end

  describe '.last_synced_at_for' do
    context 'when a sync record exists' do
      let(:synced_at) { Time.utc(2026, 4, 23, 12, 0, 0) }

      before do
        described_class.create!(aspace_config_set: 'default', repository_code: 'ars', last_synced_at: synced_at)
      end

      it 'returns the last_synced_at time' do
        expect(described_class.last_synced_at_for(repository)).to be_within(1.second).of(synced_at)
      end
    end

    context 'when no sync record exists' do
      it 'returns nil' do
        expect(described_class.last_synced_at_for(repository)).to be_nil
      end
    end
  end

  describe '.record_sync' do
    let(:synced_at) { Time.utc(2026, 4, 23, 14, 30, 0) }

    context 'when no prior record exists' do
      it 'creates a new sync record' do
        expect { described_class.record_sync(repository:, synced_at:) }
          .to change(described_class, :count).by(1)
      end

      it 'stores the synced_at time' do
        described_class.record_sync(repository:, synced_at:)
        expect(described_class.last_synced_at_for(repository)).to be_within(1.second).of(synced_at)
      end
    end

    context 'when a prior record exists' do
      before do
        described_class.create!(aspace_config_set: 'default', repository_code: 'ars',
                                last_synced_at: 1.day.ago)
      end

      it 'updates the existing record rather than creating a new one' do
        expect { described_class.record_sync(repository:, synced_at:) }
          .not_to change(described_class, :count)
      end

      it 'updates last_synced_at to the new time' do
        described_class.record_sync(repository:, synced_at:)
        expect(described_class.last_synced_at_for(repository)).to be_within(1.second).of(synced_at)
      end
    end
  end
end
