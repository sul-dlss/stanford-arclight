# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Repositories Page', type: :feature do
  before do
    visit arclight_engine.repositories_path
  end

  it 'links repositories to the search page' do
    expect(page).to have_link('Archive of Recorded Sound', href: 'http://www.example.com/catalog?f%5Blevel%5D%5B%5D=Collection&f%5Brepository%5D%5B%5D=Archive+of+Recorded+Sound')
  end
end
