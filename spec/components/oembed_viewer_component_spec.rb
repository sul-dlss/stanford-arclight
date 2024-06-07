# frozen_string_literal: true

require "rails_helper"

RSpec.describe OembedViewerComponent, type: :component do
  let(:presenter) { instance_double(Arclight::ShowPresenter) }
  let(:document) { instance_double(SolrDocument) }
  let(:resource) { instance_double(DigitalObject, href: 'example.com', label: 'hi') }

  before do
    render_inline(described_class.new(resource:, document:))
  end

  it 'renders the viewer' do
    expect(page).to have_css 'div[data-controller="sul-embed"]'
  end

  it 'renders a link to the resource' do
    expect(page).to have_link 'hi', href: 'example.com'
  end

  it 'passes the oembed URL to the viewer' do
    expect(page).to have_css 'div[data-sul-embed-url-value="example.com"]'
  end
end
