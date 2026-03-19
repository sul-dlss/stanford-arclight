# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Searching', :js do
  context 'when not within a collection' do
    before do
      visit search_catalog_path

      # Fill in the search input with some text
      fill_in 'q', with: 'Example search query'

      click_on 'Search'
    end

    it 'renders the search results page with default params' do
      expect(page).to have_content(/Your selections:\nKeyword Example search query/)
      expect(page.current_url).to include('group=true&search_field=keyword&q=Example+search+query')
    end

    it 'creates Clear all link with the group=true parameter' do
      click_on('Clear all')

      expect(page).to have_current_path(search_catalog_path(group: true))
    end
  end

  context 'when within a collection' do
    it 'does not group by collection' do
      visit solr_document_path(id: 'ars-0043')
      fill_in 'q', with: 'jazz'
      click_on 'Search'
      expect(page).to have_content(/Your selections:\nKeyword jazz/)
      expect(page.current_url).not_to include('group=true')
    end
  end

  context 'when the level facet is limited to collections' do
    it 'does not group by collection' do
      visit arclight_engine.collections_path
      fill_in 'q', with: 'knuth'
      click_on 'Search'

      expect(page).to have_content(/Your selections:\nKeyword knuth/)
      expect(page.current_url).not_to include('group=true')
    end
  end

  context 'when within a collection and user selects group by all collections' do
    it 'groups by collection' do
      visit solr_document_path(id: 'ars-0043')
      fill_in 'q', with: 'jazz'
      select('All collections', from: 'within_collection')
      click_on 'Search'
      expect(page).to have_content(/Your selections:\nKeyword jazz/)
      expect(page.current_url).to include('group=true')
    end
  end

  context 'when a query contains a dash surrounded by spaces' do
    before do
      visit search_catalog_path
      fill_in 'q', with: 'Academy of Ancient Music - Broadway Celebration'
      click_on 'Search'
    end

    it 'returns the expected number of results' do
      expect(page).to have_content(/1 collections found/)
    end
  end
end
