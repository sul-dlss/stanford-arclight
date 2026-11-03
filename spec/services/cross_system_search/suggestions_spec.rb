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
  # Always zero in these fixtures - Exhibits is dropped from sources entirely
  # (see suggestions.rb#source_from), so it never reaches the prompt either.
  let(:exhibits_result) { CrossSystemSearch::ExhibitsClient::Result.new(total: 0, docs: []) }
  let(:completion) { 'SearchWorks:: RELATED:: A digitized sound recording from the same era.' }
  let(:sent_messages) { [] }

  before do
    # Stubbed independently of ChatCompletionService so it can't be confused
    # with the Suggestions blurb call below - these examples aren't testing
    # the safety gate itself (see query_safety_spec.rb for that).
    allow(SemanticSearch::QuerySafety).to receive(:safe?).and_return(true)
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

    expect(searchworks[:total]).to eq 1204
    expect(searchworks[:tier]).to eq :strong_match
    expect(searchworks[:doc]).to eq(title: 'Jazz', url: 'https://searchworks.stanford.edu/view/1')
    expect(searchworks[:blurb_html]).to eq 'A digitized sound recording from the same era.'
    expect(searchworks[:search_url]).to eq 'https://searchworks.stanford.edu/catalog?q=jazz'
  end

  it 'drops a system with zero real results rather than showing an empty stub' do
    result = described_class.for(query: 'jazz')

    expect(result[:sources].pluck(:label)).to eq ['SearchWorks']
  end

  it 'returns nil when every system has zero real results' do
    allow(CrossSystemSearch::SearchworksClient).to receive(:new)
      .and_return(instance_double(CrossSystemSearch::SearchworksClient,
                                  search: CrossSystemSearch::SearchworksClient::Result.new(total: 0, docs: [])))

    expect(described_class.for(query: 'jazz')).to be_nil
  end

  it 'grounds the prompt in a real sample (with format) of results, not just the top doc' do
    described_class.for(query: 'jazz')

    user_message = sent_messages.find { |m| m[:role] == 'user' }[:content]
    expect(user_message).to include('Jazz (Music recording)')
    expect(user_message).to include('Jazz theory')
  end

  it 'downgrades the tier to :low_confidence when the model judges the sample unrelated to the query' do
    allow_any_instance_of(SemanticSearch::ChatCompletionService) # rubocop:disable RSpec/AnyInstance
      .to receive(:complete).and_return('SearchWorks:: UNRELATED:: Results about an unrelated historical topic.')

    searchworks = described_class.for(query: 'how do you make candy')[:sources].find { |s| s[:label] == 'SearchWorks' }

    expect(searchworks[:tier]).to eq :low_confidence
    expect(searchworks[:blurb_html]).to eq 'Results about an unrelated historical topic.'
  end

  it 'drops a source line that omits the required RELATED/UNRELATED field rather than guessing' do
    allow_any_instance_of(SemanticSearch::ChatCompletionService) # rubocop:disable RSpec/AnyInstance
      .to receive(:complete).and_return('SearchWorks:: A digitized sound recording from the same era.')

    searchworks = described_class.for(query: 'jazz')[:sources].find { |s| s[:label] == 'SearchWorks' }

    expect(searchworks[:blurb_html]).to be_nil
  end

  it 'escapes the model output rather than trusting it as HTML' do
    allow_any_instance_of(SemanticSearch::ChatCompletionService) # rubocop:disable RSpec/AnyInstance
      .to receive(:complete).and_return('SearchWorks:: RELATED:: <script>alert(1)</script>')

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
