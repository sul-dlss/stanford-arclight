# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Search', type: :feature do
  before do
    visit search_catalog_path

    # Fill in the search input with some text
    fill_in 'q', with: 'Example search query'

    click_button 'Search'
  end

  it 'Renders the search results page with default params' do
    expect(page).to have_current_path('/catalog?search_field=keyword&q=Example+search+query')

    expect(page).to have_content('You searched for: Keyword Example search query')
  end

  it 'Creates Start Over link with the group=true parameter' do
    click_link('Start Over')

    expect(page).to have_current_path(search_catalog_path(group: true))
  end
end
