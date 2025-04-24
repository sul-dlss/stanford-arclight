# frozen_string_literal: true

require 'rails_helper'
require 'active_support'
require 'active_support/testing/time_helpers'

RSpec.describe LandingPage::LibraryHoursComponent, type: :component do
  include ActiveSupport::Testing::TimeHelpers
  subject(:component) { described_class.new(key: 'spc') }

  let(:library_hours) { instance_double(LibraryHours) }

  before do
    travel_to Time.zone.parse('2024-04-12T10:00:00.000+00:00')
    allow(LibraryHours).to receive(:from_config).and_return(library_hours)
    allow(library_hours).to receive_messages(hours)
    render_inline(component)
  end

  context 'when the library is closed' do
    let(:hours) do
      {
        closed_note: nil,
        open_now?: false,
        next_open_hours: instance_double(LibraryHoursApi::Hours,
                                         opens_at_time: Time.zone.parse('2024-04-12T12:00:00.000-07:00'))
      }
    end

    it 'renders the closed icon and message' do
      expect(page).to have_css('.library-closed')
      expect(page).to have_link('Closed until 12pm', href: 'https://library-hours.stanford.edu/')
    end

    context 'when the library has a custom closed message' do
      let(:hours) { { closed_note: 'Closed until further notice', open_now?: false } }

      it 'renders the closed icon and message' do
        expect(page).to have_css('.library-closed')
        expect(page).to have_text('Closed until further notice')
      end
    end
  end

  context 'when the library is open' do
    let(:hours) do
      {
        closed_note: nil,
        open_now?: true,
        hours_today: instance_double(LibraryHoursApi::Hours,
                                     closes_at_time: Time.zone.parse('2024-04-12T17:00:00.000-07:00'))
      }
    end

    it 'renders the open icon and message' do
      expect(page).to have_no_css('.library-closed')
      expect(page).to have_text('Open until 5pm')
    end
  end

  context 'when the opening time is today' do
    context 'when the time includes minutes' do
      let(:hours) do
        {
          closed_note: nil,
          open_now?: false,
          next_open_hours: instance_double(LibraryHoursApi::Hours,
                                           opens_at_time: Time.zone.parse('2024-04-12T11:30:00.000-07:00'))
        }
      end

      it 'includes the minutes' do
        expect(page).to have_text('Closed until 11:30am')
      end
    end

    context 'when the time does not include minutes' do
      let(:hours) do
        {
          closed_note: nil,
          open_now?: false,
          next_open_hours: instance_double(LibraryHoursApi::Hours,
                                           opens_at_time: Time.zone.parse('2024-04-12T11:00:00.000-07:00'))
        }
      end

      it 'does not include the minutes' do
        expect(page).to have_text('Closed until 11am')
      end
    end

    context 'when time is noon' do
      let(:hours) do
        {
          closed_note: nil,
          open_now?: false,
          next_open_hours: instance_double(LibraryHoursApi::Hours,
                                           opens_at_time: Time.zone.parse('2024-04-12T12:00:00.000-07:00'))
        }
      end

      it { expect(page).to have_text('Closed until 12pm') }
    end

    context 'when time is midnight' do
      let(:hours) do
        {
          closed_note: nil,
          open_now?: false,
          next_open_hours: instance_double(LibraryHoursApi::Hours,
                                           opens_at_time: Time.zone.parse('2024-04-12T00:00:00.000-07:00'))
        }
      end

      it { expect(page).to have_text('Closed until 12am') }
    end
  end

  context 'when the opening time is tomorrow' do
    let(:hours) do
      {
        closed_note: nil,
        open_now?: false,
        next_open_hours: instance_double(LibraryHoursApi::Hours,
                                         opens_at_time: Time.zone.parse('2024-05-10T09:00:00.000-07:00'))
      }
    end

    it 'shows the day in addition to the time' do
      expect(page).to have_text('Closed until 9am Friday')
    end
  end

  context 'when the opening time is neither today nor tomorrow' do
    let(:hours) do
      {
        closed_note: nil,
        open_now?: false,
        next_open_hours: instance_double(LibraryHoursApi::Hours,
                                         opens_at_time: Time.zone.parse('2024-05-12T09:00:00.000-07:00'))
      }
    end

    it 'shows the day in addition to the time' do
      expect(page).to have_text('Closed until 9am Sunday')
    end
  end
end
