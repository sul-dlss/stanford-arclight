# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Feedback Form', :js do
  it 'is visible only after clicking the feedback link' do
    visit root_path

    feedback = page.find_by_id('feedback', visible: false)
    expect(feedback.native.style('visibility')).to eq('hidden')
    expect(page).to have_css('#feedback', visible: :hidden)

    click_on 'Feedback'
    within '#feedback' do
      expect(page).to have_css('form')
    end
  end
end
