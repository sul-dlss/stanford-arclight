# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Facets', type: :feature do
  context 'when viewing the Catalog page' do
    before do
      visit search_catalog_path
    end

    it 'the Access facet is first in the list and expanded' do
      expect(page).to have_css('.facets .blacklight-access:first-child', text: 'Access')
      expect(page).not_to have_css('.facets .blacklight-access .collapsed')
    end
  end
end
