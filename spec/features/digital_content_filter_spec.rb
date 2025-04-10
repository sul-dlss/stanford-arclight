# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Digital content filter' do
  context 'when viewing the Catalog page' do
    before do
      visit search_catalog_path
    end

    it 'the Digital content filter exists and is the first of the facets' do
      expect(page).to have_css('.facets #facet-digital_content:first-child', text: 'View only digital content')
    end
  end
end
