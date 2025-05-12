# frozen_string_literal: true

require 'rails_helper'

RSpec.describe EmbedComponent, type: :component do
  subject(:component) { described_class.new(document:, presenter: nil) }

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

  describe '#linked_resources' do
    let(:document) do
      SolrDocument.new(id: 'abc123',
                       digital_objects_ssm: ['{"label":"Not a link","href":"123435"}', '{"label":"Not a link","href":"https://sample/123435"}'])
    end

    it 'rejects resources that don no have valid URIs' do
      expect(component.linked_resources.length).to eq(1)
      expect(component.linked_resources.first.href).to eq('https://sample/123435')
    end
  end
end
