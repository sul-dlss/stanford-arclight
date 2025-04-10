# frozen_string_literal: true

require 'rails_helper'

RSpec.describe LandingPage::InfoCardComponent, type: :component do
  subject(:component) { described_class.new(key: 'subject_specialist') }

  before do
    render_inline(component)
  end

  it 'renders the info card' do
    expect(page).to have_text('Find a subject specialist')
    expect(page).to have_text('Have questions about Stanford University Libraries')
    expect(page).to have_link('Contact us for help')
  end
end
