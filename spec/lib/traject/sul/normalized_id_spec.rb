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
end
