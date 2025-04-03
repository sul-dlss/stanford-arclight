# frozen_string_literal: true

require 'rails_helper'

RSpec.describe SearchTipsComponent, type: :component do
  subject(:rendered) { Capybara::Node::Simple.new(render_inline(described_class.new)) }

  it 'displays a title with a subheading' do
    expect(rendered).to have_css('h1.modal-title', text: 'Search tips')
    expect(rendered).to have_css('h2', text: 'Refine your search')
  end

  it 'includes search tips text' do
    expect(rendered).to have_css('ul.pe-4 li', count: 7)
    expect(rendered).to have_content('Use quotation marks to search')
  end

  it 'includes a close button' do
    expect(rendered).to have_css('button.btn-outline-primary span', text: 'Close')
  end
end
