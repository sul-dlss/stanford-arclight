# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Range Limit Facet', :js do
  it 'does not accept an incomplete range' do
    visit search_catalog_path

    click_on 'Show facets' if page.has_button?('Show facets')

    expect(page).to have_button('Date range')
    click_on 'Date range'

    # Both empty
    expect(page).to have_no_css('input#range_date_range_begin[required]')
    expect(page).to have_no_css('input#range_date_range_end[required]')

    # Only begin has a value
    fill_in 'range_date_range_begin', with: '1986'
    expect(page).to have_css('input#range_date_range_begin[required]')
    expect(page).to have_css('input#range_date_range_end[required]')

    # Only end has a value
    fill_in 'range_date_range_begin', with: ''
    fill_in 'range_date_range_end', with: '1991'
    expect(page).to have_css('input#range_date_range_begin[required]')
    expect(page).to have_css('input#range_date_range_end[required]')

    # Both have values
    fill_in 'range_date_range_begin', with: '1986'
    fill_in 'range_date_range_end', with: '1991'
    expect(page).to have_css('input#range_date_range_begin[required]')
    expect(page).to have_css('input#range_date_range_end[required]')
  end
end
