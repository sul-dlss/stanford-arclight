# frozen_string_literal: true

require 'rails_helper'

RSpec.describe ContainersPillComponent, type: :component do
  subject(:component) { described_class.new(document:, compact:) }

  let(:document) do
    SolrDocument.new(id: 'abc123',
                     containers_ssim: ['Box 3'])
  end
  let(:compact) { false }

  before do
    render_inline(component)
  end

  it 'renders the extents' do
    expect(page).to have_text 'Box 3'
  end

  context 'when compact is true' do
    let(:compact) { true }

    it 'does not render the extents' do
      expect(page).to have_no_text 'Box 3'
    end
  end
end
