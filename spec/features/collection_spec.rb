# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Collection Page', type: :feature do
  before do
    visit search_catalog_path
    within('#facet-level') do
      click_link('Collection')
    end
  end

  context 'when visiting a collection page' do
    before do
      visit search_catalog_path
      within('#facet-level') do
        click_link('Collection')
      end
      within('#facet-repository') do
        click_link('Archive of Recorded Sound')
      end
      # Click on a specific collection
      collection_title_element = find('#documents .document-title-heading a',
                                      text: 'Ambassador Auditorium Collection, 1974-1995')
      collection_title_element.click
    end

    it 'displays the call number in the summary section' do
      within('#summary') do
        expect(page).to have_text('Call number')
      end
    end

    it 'links to the repository search page in the breadcrumbs' do
      within('.al-show-breadcrumb') do
        expect(page).to have_link('Archive of Recorded Sound', href: 'http://www.example.com/catalog?f%5Blevel%5D%5B%5D=Collection&f%5Brepository%5D%5B%5D=Archive+of+Recorded+Sound')
      end
    end

    it 'displays the normalized collection id in the URL' do
      expect(page.current_url).to eq('http://www.example.com/catalog/ars-0043_ambassador-auditorium-collection')
    end
  end

  context 'when visiting a collection page with an id derived from its title' do
    before do
      within('#facet-repository') do
        click_link('Cubberley Education Library')
      end
      collection_title_element = find('#documents .document-title-heading a',
                                      text: 'Université de Toulouse')
      collection_title_element.click
    end

    it 'displays the normalized collection id in the URL' do
      expect(page.current_url).to eq('http://www.example.com/catalog/universite-de-toulouse')
    end
  end
end
