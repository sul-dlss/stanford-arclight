# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Home Page' do
  let(:mock_library_hours) do
    instance_double(LibraryHours, label: 'Green Library',
                                  url: 'https://library.stanford.edu/libraries/cecil-h-green-library',
                                  closed_note: 'Closed',
                                  open_now?: false)
  end

  before do
    allow(LibraryHours).to receive(:new).and_return(mock_library_hours)
    visit root_path
  end

  it 'has the title and subtitle' do
    expect(page).to have_css('.blacklight-landing_page h1', text: 'Find archival materials')
    expect(page).to have_css('.blacklight-landing_page .collection-count', text: 'Detailed inventories of')
  end

  it 'has a featured item' do
    expect(page).to have_css('#featured-item-wrapper')
  end

  it 'has info cards' do
    expect(page).to have_css('h2', text: 'Find a subject specialist')
    expect(page).to have_css('h2', text: 'Using this site')
  end

  it 'has four access cards' do
    expect(page).to have_css('h3', text: 'Field Reading Room')
    expect(page).to have_css('h3', text: 'Archive of Recorded Sound')
    expect(page).to have_css('h3', text: 'East Asia Library')
    expect(page).to have_css('h3', text: 'Cubberley Education Library')
  end

  it 'has the content warning' do
    expect(page).to have_css('.content-warning')
  end

  it 'has auto-complete enabled' do
    expect(page).to have_css('.search-autocomplete-wrapper')
  end
end
