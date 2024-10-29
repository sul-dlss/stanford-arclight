# frozen_string_literal: true

require 'rails_helper'

RSpec.describe TimeService do
  include ActiveSupport::Testing::TimeHelpers

  describe '.next_half_hour' do
    it 'returns the next half-hour when the current time is exactly the half-hour' do
      travel_to Time.zone.local(2024, 5, 14, 9, 30) do
        expect(described_class.next_half_hour).to eq(Time.zone.local(2024, 5, 14, 10, 0))
      end

      travel_to Time.zone.local(2024, 5, 14, 10, 0) do
        expect(described_class.next_half_hour).to eq(Time.zone.local(2024, 5, 14, 10, 30))
      end
    end

    it 'returns the half-hour if the current time is before the half-hour' do
      travel_to Time.zone.local(2024, 5, 14, 9, 20) do
        expect(described_class.next_half_hour).to eq(Time.zone.local(2024, 5, 14, 9, 30))
      end
    end

    it 'returns the next hour if the current time is after the half-hour' do
      travel_to Time.zone.local(2024, 5, 14, 9, 40) do
        expect(described_class.next_half_hour).to eq(Time.zone.local(2024, 5, 14, 10, 0))
      end
    end

    it 'correctly handles noon' do
      travel_to Time.zone.local(2024, 5, 14, 11, 59) do
        expect(described_class.next_half_hour).to eq(Time.zone.local(2024, 5, 14, 12, 0))
      end
    end

    it 'correctly handles midnight' do
      travel_to Time.zone.local(2024, 5, 14, 23, 59) do
        expect(described_class.next_half_hour).to eq(Time.zone.local(2024, 5, 15, 0, 0))
      end
    end
  end

  describe '.seconds_until_next_half_hour' do
    it 'returns the minimum of 5 seconds when the next half-hour is less than 5 seconds away' do
      travel_to Time.zone.local(2024, 5, 14, 9, 29, 56) do
        expect(described_class.seconds_until_next_half_hour).to eq(5.seconds)
      end
    end

    it 'returns a maximum of 30 minutes' do
      allow(described_class).to receive(:next_half_hour).and_return(45.minutes.from_now)
      expect(described_class.seconds_until_next_half_hour).to eq(30.minutes)
    end

    it 'returns the correct number of seconds if the current time is within the thresholds' do
      travel_to Time.zone.local(2024, 5, 14, 9, 30) do
        expect(described_class.seconds_until_next_half_hour).to eq(30.minutes)
      end

      travel_to Time.zone.local(2024, 5, 14, 10, 0) do
        expect(described_class.seconds_until_next_half_hour).to eq(30.minutes)
      end

      travel_to Time.zone.local(2024, 5, 14, 9, 20, 30) do
        expect(described_class.seconds_until_next_half_hour).to eq(9.minutes + 30.seconds)
      end
    end
  end
end
