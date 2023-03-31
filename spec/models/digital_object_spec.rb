# frozen_string_literal: true

require 'rails_helper'

RSpec.describe DigitalObject do
  subject(:instance) do
    described_class.new(label: 'An object label', href: 'an-object-id')
  end

  describe 'label' do
    let(:empty_label) do
      described_class.new(label: '', href: 'an-object-id')
    end

    it 'uses href if label is blank' do
      expect(empty_label.href).to eq 'an-object-id'
    end
  end

  describe "#{described_class}.from_json" do
    it 'returns an instance of the class given the parsed json' do
      deserialized = described_class.from_json(instance.to_json)
      expect(deserialized).to be_a described_class
      expect(deserialized.label).to eq 'An object label'
      expect(deserialized.href).to eq 'https://purl.stanford.edu/an-object-id'
    end
  end
end
