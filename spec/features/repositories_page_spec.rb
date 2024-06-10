# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Repositories Page' do
  before do
    visit arclight_engine.repositories_path
  end

  it 'has a title' do
    expect(page).to have_title('Repositories - Archival Collections at Stanford')
  end

  it 'links repositories to their search page with collection count' do
    expect(page).to have_link('Browse 1 collection', href: 'http://www.example.com/catalog?f%5Blevel%5D%5B%5D=Collection&f%5Brepository%5D%5B%5D=Archive+of+Recorded+Sound')
  end
end
