# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Collection Page', type: :feature do
  before do
    visit search_catalog_path
    within('#facet-level') do
      click_link('Collection')
    end
    within('#facet-repository') do
      click_link('Archive of Recorded Sound')
    end
    all('#documents .document-title-heading a').first.click
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
end
