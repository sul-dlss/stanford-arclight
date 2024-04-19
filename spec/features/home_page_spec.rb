# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Home Page', type: :feature do
  let(:mock_library_hours) { instance_double(LibraryHours, label: 'Green Library', url: 'https://library.stanford.edu/libraries/cecil-h-green-library', closed_note: 'Closed') }

  before do
    allow(LibraryHours).to receive(:new).and_return(mock_library_hours)
    visit root_path
  end

  it 'has the title and subtitle' do
    expect(page).to have_css('.blacklight-landing_page h2', text: 'Find archival materials')
    expect(page).to have_css('.blacklight-landing_page .collection-count', text: 'Detailed inventories of')
  end

  it 'has a featured item' do
    expect(page).to have_css('#featured-item-wrapper')
  end

  it 'has the about section' do
    expect(page).to have_css('h2', text: 'About this site')
  end

  it 'has the three descriptive cards' do
    expect(page).to have_css('h3', text: 'Locations')
    expect(page).to have_css('h3', text: 'Request materials')
    expect(page).to have_css('h3', text: 'Ask a librarian')
  end

  it 'has the content warning' do
    expect(page).to have_css('.content-warning')
  end
end
