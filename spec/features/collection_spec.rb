# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Collection Page', type: :feature do
  it 'links to the repository search page in the breadcrumbs' do
    visit search_catalog_path
    within('#facets') do
      click_link('Archive of Recorded Sound')
    end
    all('#documents .document-title-heading a').first.click

    within('.al-show-breadcrumb') do
      expect(page).to have_link('Archive of Recorded Sound', href: 'http://www.example.com/catalog?f%5Blevel%5D%5B%5D=Collection&f%5Brepository%5D%5B%5D=Archive+of+Recorded+Sound')
    end
  end
end
