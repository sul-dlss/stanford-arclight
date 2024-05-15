# frozen_string_literal: true

require 'rails_helper'

RSpec.describe LandingPageController, type: :controller do
  include ActiveSupport::Testing::TimeHelpers

  describe '#next_half_hour' do
    it 'returns the half-hour if the current time is before the half-hour' do
      travel_to Time.zone.local(2024, 5, 14, 9, 20) do
        expect(controller.next_half_hour).to eq(Time.zone.local(2024, 5, 14, 9, 30))
      end
    end

    it 'returns the next hour if the current time is after the half-hour' do
      travel_to Time.zone.local(2024, 5, 14, 9, 40) do
        expect(controller.next_half_hour).to eq(Time.zone.local(2024, 5, 14, 10, 0))
      end
    end

    it 'correctly handles noon' do
      travel_to Time.zone.local(2024, 5, 14, 11, 59) do
        expect(controller.next_half_hour).to eq(Time.zone.local(2024, 5, 14, 12, 0))
      end
    end

    it 'correctly handles midnight' do
      travel_to Time.zone.local(2024, 5, 14, 23, 59) do
        expect(controller.next_half_hour).to eq(Time.zone.local(2024, 5, 15, 0, 0))
      end
    end
  end
end
