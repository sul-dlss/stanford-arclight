# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Home Page', type: :feature do
  it 'renders' do
    visit root_path

    expect(page).to have_css('header .h1', text: 'Archival Collections at Stanford')
  end
end
