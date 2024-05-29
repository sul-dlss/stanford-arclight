# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Feedback Form', :js, type: :feature do
  it 'is visible after clicking the feedback link' do
    visit root_path
    click_link 'Feedback'
    within '#feedback' do
      expect(page).to have_css('form')
    end
  end
end
