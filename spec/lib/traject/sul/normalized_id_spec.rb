# frozen_string_literal: true

require 'rails_helper'
require 'traject/sul/normalized_id'

RSpec.describe Sul::NormalizedId do
  subject(:normalized_id) { described_class.new(ead_id, title:).to_s }

  let(:ead_id) { 'abc1234' }
  let(:title) { 'A Collection of Papers' }

  it 'returns a normalized id' do
    expect(normalized_id).to eq 'abc1234_a-collection-of-papers'
  end

  context 'when the title is empty' do
    let(:title) { '' }

    it 'returns a normalized id using the eadid' do
      expect(normalized_id).to eq 'abc1234'
    end
  end

  context 'when the title has over 5 words' do
    let(:title) do
      'Lopez v. Monterey County : photocopies of court case research ' \
        'documenting historical discrimination against Mexicans in Monterey County, California'
    end

    it 'returns a normalized id using the first 5 words' do
      expect(normalized_id).to eq 'abc1234_lopez-v-monterey-county-photocopies'
    end
  end

  context 'when the title contains words that parameterize would make into empty strings' do
    let(:title) { 'Универзитет „Кирил и Методиј" во Скопје/Ss. Cyril and Methodius University of Skopje' }

    it 'returns a normalized id using the first 5 non-empty parameterized words' do
      expect(normalized_id).to eq 'abc1234_ss-cyril-and-methodius-university'
    end
  end

  context 'when the title contains only words that parameterize would make into empty strings' do
    let(:title) { 'Универзитет „Кирил и Методиј" во Скопје' }

    it 'returns a normalized id using the eadid' do
      expect(normalized_id).to eq 'abc1234'
    end
  end

  context 'when the title and the eadid are the same' do
    let(:ead_id) { 'Université de Toulouse' }
    let(:title) { ead_id }

    it 'returns a normalized id without duplication' do
      expect(normalized_id).to eq 'universite-de-toulouse'
    end
  end

  context 'when the eadid is empty' do
    let(:ead_id) { '' }

    it 'returns a normalized id' do
      expect(normalized_id).to eq 'a-collection-of-papers'
    end
  end

  context 'when the eadid is nil' do
    let(:ead_id) { nil }

    it 'returns a normalized id' do
      expect(normalized_id).to eq 'a-collection-of-papers'
    end
  end

  context 'when both the title and eadid are empty' do
    let(:ead_id) { '' }
    let(:title) { '' }

    it 'raises an error' do
      expect { normalized_id }.to raise_error(Arclight::Exceptions::IDNotFound)
    end
  end
end
