# frozen_string_literal: true

require 'rails_helper'

RSpec.describe LandingPageHelper, type: :helper do
  describe '#format_hours' do
    context 'when given an empty time' do
      it 'returns the empty string' do
        expect(format_hours(nil)).to eq('')
      end
    end

    context 'when the hours have a closed note' do
      let(:hours) { instance_double(LibraryHours, closed_note: 'closed forever') }

      it 'returns the closed note' do
        expect(format_hours(hours)).to eq('closed forever')
      end
    end

    context 'when given hours for when the library is currently open' do
      let(:time) { Time.current.change(hour: 17, min: 0) }
      let(:hours_today) { instance_double(LibraryHoursApi::Hours, closes_at_time: time) }
      let(:open_hours) { instance_double(LibraryHours, open_now?: true, hours_today:, closed_note: nil) }

      it 'returns the "Open until" message with the closing time' do
        expect(format_hours(open_hours)).to eq('Open until 5pm')
      end
    end

    context 'when given hours for when the library is currently closed' do
      let(:time) { Time.current.change(hour: 9, min: 0) + 1.day }
      let(:next_open_hours) { instance_double(LibraryHoursApi::Hours, opens_at_time: time) }
      let(:open_hours) { instance_double(LibraryHours, open_now?: false, next_open_hours:, closed_note: nil) }

      it 'returns the "Closed until" message with the next opening time' do
        expect(format_hours(open_hours)).to eq('Closed until 9am')
      end
    end
  end

  describe '#format_time' do
    context 'when the time is today' do
      it 'shows the minutes when minutes are non-zero' do
        time = Time.current.change(hour: 10, min: 30)
        expect(format_time(time)).to eq('10:30am')
      end

      it 'removes the minutes when minutes are zero' do
        time = Time.current.change(hour: 10, min: 0)
        expect(format_time(time)).to eq('10am')
      end

      it 'handles noon' do
        time = Time.current.change(hour: 12, min: 0)
        expect(format_time(time)).to eq('12pm')
      end

      it 'handles midnight' do
        time = Time.current.change(hour: 0, min: 0)
        expect(format_time(time)).to eq('12am')
      end
    end

    context 'when the time is tomorrow' do
      it 'shows the day in addition to the time' do
        time = Time.current.change(hour: 10, min: 30) + 1.day
        expect(format_time(time)).to eq('10:30am')
      end
    end

    context 'when the time is not today or tomorrow' do
      it 'shows the day in addition to the time' do
        time = Time.current.change(hour: 10, min: 30) + 2.days
        expect(format_time(time)).to eq("10:30am #{time.strftime('%A')}")
      end
    end
  end
end
