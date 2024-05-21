# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Beta banner', type: :feature do
  context 'when the beta banner is enabled' do
    before do
      allow(Settings.beta_banner).to receive(:enabled).and_return(true)
    end

    it 'displays on the landing page' do
      visit root_path
      expect(page).to have_css('.beta-banner')
    end

    it 'appears on the catalog page' do
      visit search_catalog_path
      expect(page).to have_css('.beta-banner')
    end

    it 'appears on the repositories page' do
      visit arclight_engine.repositories_path
      expect(page).to have_css('.beta-banner')
    end
  end

  context 'when the beta banner is disabled' do
    before do
      allow(Settings.beta_banner).to receive(:enabled).and_return(false)
      visit root_path
    end

    it 'does not show the beta banner' do
      expect(page).not_to have_css('.beta-banner')
    end
  end
end
