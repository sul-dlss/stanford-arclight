# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Search Catalog Page', type: :feature do
  before do
    visit search_catalog_path
  end

  it 'links repositories in search results to their search page' do
    within('#facets') do
      click_link('Archive of Recorded Sound')
    end

    within('#documents') do
      expect(page).to have_link('Archive of Recorded Sound', href: 'http://www.example.com/catalog?f%5Blevel%5D%5B%5D=Collection&f%5Brepository%5D%5B%5D=Archive+of+Recorded+Sound')
    end

    click_link('Grouped by collection')
    within('#documents') do
      expect(page).to have_link('Archive of Recorded Sound', href: 'http://www.example.com/catalog?f%5Blevel%5D%5B%5D=Collection&f%5Brepository%5D%5B%5D=Archive+of+Recorded+Sound')
    end
  end
end
