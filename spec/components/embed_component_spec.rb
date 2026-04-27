# frozen_string_literal: true

require 'rails_helper'

RSpec.describe EmbedComponent, type: :component do
  subject(:component) { described_class.new(presenter: presenter) }

  let(:presenter) do
    Blacklight::DocumentPresenter.new(document, request_context)
  end
  let(:blacklight_config) { Blacklight::Configuration.new }
  let(:request_context) { double('View context', blacklight_config: blacklight_config) } # rubocop:disable RSpec/VerifiedDoubles
  let(:document) do
    SolrDocument.new(id: 'abc123',
                     digital_objects_ssm: ['{"label":"Preparing books for publication (3)","href":"jp131ht4213"}'])
  end

  before do
    render_inline(component)
  end

  it 'renders the embeddable resource' do
    expect(page).to have_text('Preparing books for publication (3)')
  end

  describe '#embeddable_resources' do
    it 'selects the first embeddable resource' do
      expect(component.embeddable_resources.first.href).to eq('https://purl.stanford.edu/jp131ht4213')
    end
  end
end
