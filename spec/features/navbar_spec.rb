# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Navbar' do
  context 'when not on the landing page' do
    before do
      visit search_catalog_path
    end

    it "renders the 'Bookmark' and 'Search History' navigation items" do
      expect(page).to have_css('#user-util-collapse .nav-item', count: 6)
      expect(page).to have_css('#user-util-collapse .nav-item a', text: 'Bookmarks')
      expect(page).to have_css('#user-util-collapse .nav-item a', text: 'History')
      expect(page).to have_css('#user-util-collapse .nav-item.d-md-none a', text: 'Repositories')
      expect(page).to have_css('#user-util-collapse .nav-item.d-md-none a', text: 'Collections')
    end

    it "always renders the 'Feedback' navigation item" do
      expect(page).to have_css('#user-util-collapse .nav-item a', text: 'Feedback')
    end
  end

  context 'when on the landing page' do
    before do
      visit root_path
    end

    it "does not render 'Bookmark' and 'Search History' navigation items" do
      expect(page).to have_css('.navbar-nav .nav-item', count: 1)
      expect(page).to have_no_css('.navbar-nav .nav-item', text: 'Bookmarks')
      expect(page).to have_no_css('.navbar-nav .nav-item', text: 'History')
    end

    it "always renders the 'Feedback' navigation item" do
      expect(page).to have_css('#user-util-collapse .nav-item a', text: 'Feedback')
    end
  end
end
