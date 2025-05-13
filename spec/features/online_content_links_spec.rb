# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'OnlineContentLinks', :js do
  before do
    visit '/catalog/sc0097_aspace_ref33_thm'
  end

  it 'has a link to the non-embedded online content' do
    expect(page).to have_link('A non-embedded online content link', href: 'https://purl.stanford.edu/zc892pd6364')
  end

  it 'removes the link to the non-embedded online content' do
    expect(page).to have_css(".al-oembed-viewer[loaded='loaded']")
    expect(page).to have_no_link('Comments on student answers (2)', href: 'https://purl.stanford.edu/vz772ry6707')
  end
end
