# frozen_string_literal: true

require 'rails_helper'

RSpec.describe LibraryHours do
  let(:an_open_time) { Time.zone.parse('2024-04-12T10:30:00.000-07:00') }
  let(:a_closed_time) { Time.zone.parse('2024-04-13T10:30:00.000-07:00') }
  let(:library_hours) do
    described_class.new(label: 'Library', library_slug: 'spc', location_slug: 'field-reading-room', url: 'https://library.stanford.edu/libraries/cecil-h-green-library')
  end
  let(:mock_hours) do
    [
      LibraryHoursApi::Hours.new({
                                   'opens_at' => '2024-04-12T09:00:00.000-07:00',
                                   'closes_at' => '2024-04-12T17:00:00.000-07:00',
                                   'open' => true
                                 }),
      LibraryHoursApi::Hours.new({
                                   'opens_at' => '2024-04-13T00:00:00.000-07:00',
                                   'closes_at' => '2024-04-13T00:00:00.000-07:00',
                                   'open' => false
                                 }),
      LibraryHoursApi::Hours.new({
                                   'opens_at' => '2024-04-14T00:00:00.000-07:00',
                                   'closes_at' => '2024-04-14T00:00:00.000-07:00',
                                   'open' => false
                                 }),
      LibraryHoursApi::Hours.new({
                                   'opens_at' => '2024-04-15T09:00:00.000-07:00',
                                   'closes_at' => '2024-04-15T17:00:00.000-07:00',
                                   'open' => true
                                 })
    ]
  end

  before do
    allow(library_hours).to receive(:weekly_library_hours).and_return(mock_hours)
  end

  describe '#open_now?' do
    context 'when the library is open now' do
      it 'returns true' do
        allow(library_hours).to receive(:now).and_return(an_open_time)
        expect(library_hours.open_now?).to be(true)
      end
    end

    context 'when the library is closed now' do
      it 'returns false' do
        allow(library_hours).to receive(:now).and_return(a_closed_time)
        expect(library_hours.open_now?).to be(false)
      end
    end
  end

  describe '#next_open_hours' do
    context 'when the library is currently closed' do
      it 'returns the next open hours' do
        allow(library_hours).to receive(:now).and_return(a_closed_time)
        expect(library_hours.next_open_hours.opens_at_time).to eq(Time.zone.parse('2024-04-15T09:00:00.000-07:00'))
      end
    end

    context 'when the library is currently open' do
      it 'returns the open hours for the next day' do
        allow(library_hours).to receive(:now).and_return(an_open_time)
        expect(library_hours.next_open_hours.opens_at_time).to eq(Time.zone.parse('2024-04-15T09:00:00.000-07:00'))
      end
    end
  end

  describe '#hours_today' do
    it 'returns the library hours for today' do
      expect(library_hours.hours_today.opens_at_time).to eq(Time.zone.parse('2024-04-12T09:00:00.000-07:00'))
      expect(library_hours.hours_today.closes_at_time).to eq(Time.zone.parse('2024-04-12T17:00:00.000-07:00'))
    end
  end
end
