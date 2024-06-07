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
      expect(page.current_url).to include('search_field=keyword&q=Example+search+query')
      expect(page.current_url).to include('group=true')

      expect(page).to have_content(/You searched for:\s*Keyword Example search query/)
    end

    it 'creates Start Over link with the group=true parameter' do
      click_on('Start Over')

      expect(page).to have_current_path(search_catalog_path(group: true))
    end
  end

  context 'when within a collection' do
    it 'does not group by collection' do
      visit solr_document_path(id: 'ars-0043_ambassador-auditorium-collection')
      fill_in 'q', with: 'jazz'
      click_on 'search'
      expect(page.current_url).not_to include('group=true')
    end
  end

  context 'when within a collection and user selects group by all collections' do
    it 'groups by collection' do
      visit solr_document_path(id: 'ars-0043_ambassador-auditorium-collection')
      fill_in 'q', with: 'jazz'
      select('all collections', from: 'within_collection')
      click_on 'search'
      expect(page.current_url).to include('group=true')
    end
  end
end
