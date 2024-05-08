# frozen_string_literal: true

require 'rails_helper'

RSpec.describe LibraryHoursApi do
  subject(:request) { LibraryHoursApi::Request.new(library, location, range) }

  let(:library) { 'green' }
  let(:location) { 'library-circulation' }
  let(:range) { {} }

  describe 'bad JSON' do
    # rubocop:disable RSpec/SubjectStub
    before do
      allow(request).to receive_messages(response: '<html />')
    end
    # rubocop:enable RSpec/SubjectStub

    it 'returns an empty hash' do
      expect(request.json).to(be {})
    end
  end

  describe 'ConnectionFailed' do
    before do
      allow(Faraday.default_connection).to receive(:get).and_raise(Faraday::ConnectionFailed, '')
    end

    it 'returns a blank response' do
      expect(request.json).to be_blank
    end
  end

  describe '#api_url' do
    let(:api_url) { request.hours_request(range).send(:api_url) }

    it 'constructs a url containing the library slug' do
      expect(request.api_url).to match(%r{/libraries/green/})
    end

    it 'constructs a url containing the location slug' do
      expect(request.api_url).to match(%r{/locations/library-circulation/})
    end

    context 'with a range' do
      let(:range) { { from: 'a', to: 'b' } }

      it 'constructs a url containing a date range of two months from today' do
        expect(request.api_url).to include('from=a')
        expect(request.api_url).to include('to=b')
      end
    end
  end

  describe LibraryHoursApi::Response do
    subject(:response) { described_class.new(data) }

    let(:data) { { 'data' => { 'attributes' => { 'hours' => hours_data } } } }
    let(:hours_data) { [] }

    describe '#open?' do
      context 'with hours the location is open' do
        let(:hours_data) { [{ 'open' => true }] }

        it 'is true' do
          expect(response).to be_open
        end
      end

      context 'without hours' do
        it 'is not open' do
          expect(response).not_to be_open
        end
      end
    end

    describe '#open_hours' do
      let(:hours_data) { [{ 'open' => true }, { 'open' => false }, { 'open' => true }] }

      it 'selects only the hours that the location is open' do
        expect(response.open_hours.length).to eq 2
      end
    end

    describe '#hours' do
      let(:hours_data) { [{ 'open' => true, 'opens_at' => Time.zone.now.to_s }] }

      it 'provides accessors to the library hours' do
        expect(response.hours.length).to eq 1
        hour = response.hours.first

        expect(hour).to be_open
        expect(hour.day).to eq Time.zone.today
      end

      context 'when there are no hours in the response' do
        let(:data) { { 'data' => { 'attributes' => nil } } }

        it 'is an empty array (and does not throw error)' do
          expect(response.hours).to eq([])
        end
      end
    end
  end
end
