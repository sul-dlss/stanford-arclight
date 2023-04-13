# frozen_string_literal: true

require 'rails_helper'

RSpec.describe DigitalObject do
  subject(:instance) do
    described_class.new(label: 'An object label', href: 'aa111bb2222')
  end

  describe 'label' do
    let(:empty_label) do
      described_class.new(label: '', href: 'aa111bb2222')
    end

    it 'uses href if label is blank' do
      expect(empty_label.href).to eq 'aa111bb2222'
    end
  end

  describe "#{described_class}.from_json" do
    it 'returns an instance of the class given the parsed json' do
      deserialized = described_class.from_json(instance.to_json)
      expect(deserialized).to be_a described_class
      expect(deserialized.label).to eq 'An object label'
      expect(deserialized.href).to eq 'https://purl.stanford.edu/aa111bb2222'
    end
  end

  describe "#{described_class}.normalize_href" do
    it 'returns the href unchanged if it contains something other than a druid' do
      expect(described_class.normalize_href('some-other-id')).to eq 'some-other-id'
    end

    it 'returns the href unchanged if it contains a URL that is not a Purl' do
      expect(described_class.normalize_href('http://www.somewebsite/some-other-id')).to eq 'http://www.somewebsite/some-other-id'
    end

    it 'returns the href unchanged if it contains a complete Purl URL' do
      expect(described_class.normalize_href('https://purl.stanford.edu/aa111bb2222')).to eq 'https://purl.stanford.edu/aa111bb2222'
    end

    it 'returns the Purl URL but converts http to https' do
      expect(described_class.normalize_href('http://purl.stanford.edu/aa111bb2222')).to eq 'https://purl.stanford.edu/aa111bb2222'
    end

    it 'returns a complete Purl URL if the href only contains a druid' do
      expect(described_class.normalize_href('aa111bb2222')).to eq 'https://purl.stanford.edu/aa111bb2222'
    end
  end
end
