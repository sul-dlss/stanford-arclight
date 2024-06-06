# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Feedback Form', :js, type: :feature do
  it 'is visible only after clicking the feedback link' do
    visit root_path

    feedback = page.find(:css, '#feedback', visible: false)
    expect(feedback.native.style('visibility')).to eq('hidden')
    expect(page).to have_css('#feedback', visible: :hidden)

    click_link 'Feedback'
    within '#feedback' do
      expect(page).to have_css('form')
    end
  end
end
