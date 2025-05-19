# frozen_string_literal: true

require 'rails_helper'

RSpec.describe ExtentPillComponent, type: :component do
  subject(:component) { described_class.new(document:, compact:) }

  let(:document) do
    SolrDocument.new(id: 'abc123',
                     extent_ssm: ['1 Box', 'This is an extensive extent so we should truncate it'])
  end
  let(:compact) { false }

  before do
    render_inline(component)
  end

  it 'renders the extents' do
    expect(page).to have_text '1 Box; This is an extensive...'
  end

  context 'when compact is true' do
    let(:compact) { true }

    it 'does not render the extents' do
      expect(page).to have_no_text '1 Box'
      expect(page).to have_no_text 'This is an extensive extent so....'
    end
  end
end
