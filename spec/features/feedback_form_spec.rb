# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Feedback Form', :js do
  it 'is visible only after clicking the feedback link' do
    visit root_path

    # The feedback link is nested within the collapsible menu for smaller screens
    # Chrome headless driver was defaulting to 756px width, breaking this test.
    page.driver.browser.manage.window.resize_to(800, 800)

    expect(page).to have_no_css('#feedback')
    click_on 'Feedback'
    within '#feedback' do
      expect(page).to have_css('form[name="feedback_form"]')
    end
  end
end
