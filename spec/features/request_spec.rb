# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Request', type: :feature do
  before do
    visit '/catalog/ARS-0043_aspace_ref463_1bu'
  end

  it 'has an Aeon request button' do
    expect(page).to have_link(
      'Request',
      href: 'https://stanford.aeon.atlas-sys.com/logon' \
            '?Action=10&Form=31' \
            '&Value=http%3A%2F%2Fwww.example.com%2Fdownload%2FARS-0043_aspace_ref463_1bu.xml' \
            '%3Fwithout_namespace%3Dtrue'
    )
  end
end
