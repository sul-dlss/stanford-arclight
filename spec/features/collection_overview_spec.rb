# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Collection sidebar' do
  before do
    visit search_catalog_path
    within('#facet-level') do
      click_on('Collection')
    end
    within('#facet-repository') do
      click_on('Archive of Recorded Sound')
    end
    find('#documents .document-title-heading a', text: 'Ambassador Auditorium Collection, 1974-1995').click
  end

  let(:expand_button) { find_by_id('collection-nav') }

  it 'displays the expand button and collapsed section' do
    expect(page).to have_css('#collection-info.collapse:not(.show)')
    expect(expand_button['aria-expanded']).to eq('false')
  end

  it 'displays the using these materials section' do
    expect(page).to have_text 'Using these materials'
  end
end
