# frozen_string_literal: true

require 'rails_helper'

RSpec.describe SemanticSearch::TextBuilder do
  subject(:text) { described_class.new(output_hash).call }

  context 'with prose and controlled-access terms' do
    let(:output_hash) do
      {
        'normalized_title_ssm' => ['Jane Doe Papers'],
        'scopecontent_tesim' => ['Correspondence and diaries.'],
        'access_subjects_ssim' => ['Women authors', 'Diaries'],
        'names_ssim' => ['Doe, Jane'],
        'places_ssim' => ['California']
      }
    end

    it 'concatenates prose then a labeled controlled-access list' do
      expect(text).to eq(
        "Jane Doe Papers\nCorrespondence and diaries.\n\n" \
        'Subjects: Women authors; Diaries. Names: Doe, Jane. Places: California.'
      )
    end
  end

  context 'when a category has more terms than the cap' do
    let(:many) { (1..30).map { |i| "Term #{i}" } }
    let(:output_hash) { { 'normalized_title_ssm' => ['A title'], 'access_subjects_ssim' => many } }

    it 'caps the number of terms per category' do
      subjects = text[/Subjects: (.+?)\./, 1].split('; ')
      expect(subjects.size).to eq(described_class::TERMS_PER_CATEGORY)
      expect(subjects.first).to eq('Term 1')
    end
  end

  context 'when the prose exceeds the character budget' do
    let(:output_hash) do
      {
        'normalized_title_ssm' => ['Big Collection'],
        'bioghist_tesim' => ['x' * 60_000],
        'access_subjects_ssim' => %w[War Peace],
        'names_ssim' => ['Doe, Jane']
      }
    end

    it 'trims the prose but keeps the title and all controlled-access terms' do
      expect(text.length).to be <= described_class::MAX_EMBED_CHARS
      expect(text).to start_with('Big Collection')
      expect(text).to end_with('Subjects: War; Peace. Names: Doe, Jane.')
    end
  end

  context 'when the document has no embeddable text' do
    let(:output_hash) { { 'id' => ['abc123'], 'level_ssim' => ['file'] } }

    it 'returns nil so the caller can skip it' do
      expect(text).to be_nil
    end
  end

  it 'de-duplicates and strips blank values' do
    result = described_class.new(
      'normalized_title_ssm' => ['  Repeated  ', 'Repeated', ''],
      'names_ssim' => ['A', 'A', ' ']
    ).call
    expect(result).to eq("Repeated\n\nNames: A.")
  end

  it 'embeds a title-only doc (we index everything; no thin-doc skipping)' do
    expect(described_class.new('normalized_title_ssm' => ['Correspondence 1985']).call).to eq('Correspondence 1985')
  end

  it 'drops the repository name from names (Arclight sweeps the <repository> corpname into names_ssim)' do
    result = described_class.new(
      'normalized_title_ssm' => ['Kirsten Flagstad Collection'],
      'repository_ssim' => ['Archive of Recorded Sound'],
      'names_ssim' => ['Archive of Recorded Sound', 'Flagstad, Kirsten']
    ).call
    expect(result).to eq("Kirsten Flagstad Collection\n\nNames: Flagstad, Kirsten.")
  end
end
