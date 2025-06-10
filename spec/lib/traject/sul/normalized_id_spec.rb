# frozen_string_literal: true

require 'rails_helper'
require 'traject/sul/normalized_id'

RSpec.describe Sul::NormalizedId do
  subject(:normalized_id) { described_class.new(ead_id, title:, unitid:).to_s }

  let(:ead_id) { 'abc1234' }
  let(:unitid) { 'def5678' }
  let(:title) { 'A Collection of Papers' }

  it 'returns a normalized id' do
    expect(normalized_id).to eq 'abc1234'
  end

  context 'when an eadid, unitid, and title are present' do
    it 'returns a normalized id using the eadid' do
      expect(normalized_id).to eq 'abc1234'
    end
  end

  context 'when the eadid looks like a title' do
    let(:ead_id) { 'Université de Toulouse' }
    let(:title) { 'Some title' }

    it 'returns a normalized for of the id suitable for an id' do
      expect(normalized_id).to eq 'universite-de-toulouse'
    end
  end

  context 'when the eadid is a string with a file extension' do
    let(:ead_id) { 'abc1234.xml' }

    it 'returns a normalized id without the file extension' do
      expect(normalized_id).to eq 'abc1234'
    end
  end

  context 'when the eadid is nil' do
    let(:ead_id) { nil }

    it 'returns a normalized id formed from the unitid' do
      expect(normalized_id).to eq 'def5678'
    end
  end

  context 'when the eadid and unitid are both nil' do
    let(:ead_id) { nil }
    let(:unitid) { nil }

    it 'returns a normalized id formed from the title' do
      expect(normalized_id).to eq 'a-collection-of-papers'
    end
  end

  context 'when the eadid and unitid are empty' do
    let(:ead_id) { '' }
    let(:unitid) { '' }

    it 'returns a normalized id formed from the title' do
      expect(normalized_id).to eq 'a-collection-of-papers'
    end

    context 'when the title has over 5 words' do
      let(:title) do
        'Lopez v. Monterey County : photocopies of court case research ' \
          'documenting historical discrimination against Mexicans in Monterey County, California'
      end

      it 'returns a normalized id using the first 5 words' do
        expect(normalized_id).to eq 'lopez-v-monterey-county-photocopies'
      end
    end

    context 'when the title contains words that parameterize would make into empty strings' do
      let(:title) { 'Универзитет „Кирил и Методиј" во Скопје/Ss. Cyril and Methodius University of Skopje' }

      it 'returns a normalized id using the first 5 non-empty parameterized words' do
        expect(normalized_id).to eq 'ss-cyril-and-methodius-university'
      end
    end

    context 'when the title is empty' do
      let(:title) { '' }

      it 'raises an error' do
        expect { normalized_id }.to raise_error(Arclight::Exceptions::IDNotFound)
      end
    end

    context 'when parameterize turns the title into an empty string' do
      let(:title) { 'Универзитет „Кирил и Методиј" во Скопје' }
      let(:ead_id) { '' }

      it 'raises an error' do
        expect { normalized_id }.to raise_error(Arclight::Exceptions::IDNotFound)
      end
    end
  end
end
