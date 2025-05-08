# frozen_string_literal: true

require 'rails_helper'

RSpec.describe OnlineContentPopoverComponent, type: :component do
  subject(:component) { described_class.new }

  before do
    render_inline(component)
  end

  it 'renders the button for the popover' do
    expect(page).to have_css '.al-online-content-icon'
    expect(page).to have_css 'button[data-bs-toggle="popover"]'
    expect(page).to have_css 'button[data-bs-content="Includes digital content"]'
  end
end
