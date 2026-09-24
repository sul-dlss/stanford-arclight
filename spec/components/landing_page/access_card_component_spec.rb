# frozen_string_literal: true

require 'rails_helper'

RSpec.describe LandingPage::AccessCardComponent, type: :component do
  subject(:component) { described_class.new(key: 'spc') }

  let(:hours_component) { instance_double(LandingPage::LibraryHoursComponent) }

  before do
    allow(hours_component).to receive(:render_in).and_return('Open until 5:00 PM')
    allow(LandingPage::LibraryHoursComponent).to receive(:new).and_return(hours_component)
    render_inline(component)
  end

  it 'renders the access card' do
    expect(page).to have_text('Field Reading Room')
    expect(page).to have_text('Located on the second floor of Green Library West.')
    expect(page).to have_text('Open until 5:00 PM')
    expect(page).to have_link('How to request materials')
  end
end
