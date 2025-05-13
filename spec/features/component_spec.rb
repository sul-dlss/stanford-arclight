# frozen_string_literal: true

require 'rails_helper'

# It would be ideal to write a component test for the DocumentComponent but this feature test works for now
RSpec.describe 'Component Page' do
  before do
    visit search_catalog_path
    within('#facet-level') do
      click_on('File')
    end
  end

  context 'when visiting a component page' do
    before do
      visit search_catalog_path
      within('#facet-level') do
        click_on('File')
      end
      within('#facet-repository') do
        click_on('Archive of Recorded Sound')
      end
      # Click on a specific file
      component_title_element = find('#documents .document-title-heading a',
                                     text: 'Audio Recordings: Radio Promotional Spots:, 1981 -- 1995', match: :first)

      component_title_element.click
    end

    it 'does not display the using these materials section' do
      expect(page).to have_no_text 'Using these materials'
    end

    it 'displays component-level metadata' do
      expect(page).to have_css('#about-this-level')
    end

    it 'links to the collection in the breadcrumbs' do
      within('.al-show-breadcrumb') do
        expect(page).to have_link('Ambassador Auditorium Collection, 1974-1995', href: '/catalog/ars-0043')
      end
    end
  end
end
