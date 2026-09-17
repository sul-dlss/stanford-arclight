# frozen_string_literal: true

require 'rails_helper'

RSpec.describe CrossSystemSearch::Suggestions do
  let(:searchworks_result) do
    CrossSystemSearch::SearchworksClient::Result.new(
      total: 1204,
      docs: [{ 'id' => '1', 'title_display' => 'Jazz', 'format_main_ssim' => ['Music recording'] },
             { 'id' => '2', 'title_display' => 'Jazz theory' }]
    )
  end
  let(:exhibits_result) { CrossSystemSearch::ExhibitsClient::Result.new(total: 0, docs: []) }
  let(:completion) do
    "SearchWorks:: A digitized sound recording from the same era.\nExhibits:: No related results found."
  end
  let(:sent_messages) { [] }

  before do
    allow(CrossSystemSearch::SearchworksClient).to receive(:new)
      .and_return(instance_double(CrossSystemSearch::SearchworksClient, search: searchworks_result))
    allow(CrossSystemSearch::ExhibitsClient).to receive(:new)
      .and_return(instance_double(CrossSystemSearch::ExhibitsClient, search: exhibits_result))
    allow_any_instance_of(SemanticSearch::ChatCompletionService) # rubocop:disable RSpec/AnyInstance
      .to receive(:complete) do |_instance, messages, **_kwargs|
        sent_messages.replace(messages)
        completion
      end
  end

  it 'builds sources with real totals/tiers, the real top doc as its own link, and a plain-text caption' do
    result = described_class.for(query: 'jazz')
    searchworks = result[:sources].find { |s| s[:label] == 'SearchWorks' }
    exhibits = result[:sources].find { |s| s[:label] == 'Exhibits' }

    expect(searchworks[:total]).to eq 1204
    expect(searchworks[:tier]).to eq :strong_match
    expect(searchworks[:doc]).to eq(title: 'Jazz', url: 'https://searchworks.stanford.edu/view/1')
    expect(searchworks[:blurb_html]).to eq 'A digitized sound recording from the same era.'
    expect(searchworks[:search_url]).to eq 'https://searchworks.stanford.edu/catalog?q=jazz'

    expect(exhibits[:total]).to eq 0
    expect(exhibits[:tier]).to eq :no_match
    expect(exhibits[:doc]).to be_nil
    expect(exhibits[:blurb_html]).to eq 'No related results found.'
    expect(exhibits[:search_url]).to eq 'https://exhibits.stanford.edu/search?q=jazz&search_field=default'
  end

  it 'grounds the prompt in a real sample (with format) of results, not just the top doc' do
    described_class.for(query: 'jazz')

    user_message = sent_messages.find { |m| m[:role] == 'user' }[:content]
    expect(user_message).to include('Jazz (Music recording)')
    expect(user_message).to include('Jazz theory')
  end

  it 'downgrades the tier to :low_confidence when the model flags the sample as unrelated to the query' do
    phrase = CrossSystemSearch::Suggestions::UNRELATED_PHRASE
    unrelated = "SearchWorks:: #{phrase}\nExhibits:: No related results found."
    allow_any_instance_of(SemanticSearch::ChatCompletionService) # rubocop:disable RSpec/AnyInstance
      .to receive(:complete).and_return(unrelated)

    searchworks = described_class.for(query: 'how do you make candy')[:sources].find { |s| s[:label] == 'SearchWorks' }

    expect(searchworks[:tier]).to eq :low_confidence
    expect(searchworks[:blurb_html]).to eq CrossSystemSearch::Suggestions::UNRELATED_PHRASE
  end

  it 'escapes the model output rather than trusting it as HTML' do
    allow_any_instance_of(SemanticSearch::ChatCompletionService) # rubocop:disable RSpec/AnyInstance
      .to receive(:complete).and_return("SearchWorks:: <script>alert(1)</script>\nExhibits:: No related results found.")

    searchworks = described_class.for(query: 'jazz')[:sources].find { |s| s[:label] == 'SearchWorks' }

    expect(searchworks[:blurb_html]).not_to include('<script>')
    expect(searchworks[:blurb_html]).to include('&lt;script&gt;')
  end

  it 'returns nil when both sources fail' do
    allow(CrossSystemSearch::SearchworksClient).to receive(:new)
      .and_return(instance_double(CrossSystemSearch::SearchworksClient, search: nil))
    allow(CrossSystemSearch::ExhibitsClient).to receive(:new)
      .and_return(instance_double(CrossSystemSearch::ExhibitsClient, search: nil))

    expect(described_class.for(query: 'jazz')).to be_nil
  end

  it 'returns nil for a blank query without calling any client' do
    described_class.for(query: '')

    expect(CrossSystemSearch::SearchworksClient).not_to have_received(:new)
  end
end
