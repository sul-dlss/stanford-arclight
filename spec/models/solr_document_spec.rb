# frozen_string_literal: true

require 'rails_helper'

RSpec.describe SolrDocument do
  describe 'custom accessors' do
    let(:document) { described_class.new }

    it { expect(document).to respond_to(:ead_filename) }
  end

  describe 'digital objects' do
    let(:document) do
      described_class.new(
        digital_objects_ssm: [
          { href: 'example01', label: 'Label 1' }.to_json,
          { href: 'example02', label: 'Label 2' }.to_json
        ]
      )
    end

    describe '#digital_objects' do
      context 'when the document has a digital object' do
        it 'is array of DigitalObjects' do
          expect(document.digital_objects.length).to eq 2
          document.digital_objects.all? do |object|
            expect(object).to be_a DigitalObject
          end
        end
      end

      context 'when the document does not have a digital object' do
        let(:document) { described_class.new }

        it 'is a blank array' do
          expect(document.digital_objects).to be_blank
        end
      end
    end
  end

  describe '#ead_file_without_namespace_href' do
    let(:document) do
      described_class.new(
        id: 'ars0001'
      )
    end

    it 'returns the href for the EAD file without a namespace' do
      expect(document.ead_file_without_namespace_href).to eq '/download/ars0001.xml?without_namespace=true'
    end
  end

  describe '#collection?' do
    context 'when the document is a collection' do
      let(:document) { described_class.new(level_ssm: ['collection'], component_level_isim: [0]) }

      it { expect(document.collection?).to be true }
    end

    context 'when the document is a file' do
      let(:document) { described_class.new(level_ssm: ['file'], component_level_isim: [0]) }

      it { expect(document.collection?).to be false }
    end

    context 'when the document is labeled as a collection but is a lower level compoment' do
      let(:document) { described_class.new(level_ssm: ['Collection'], component_level_isim: [2]) }

      it { expect(document.collection?).to be false }
    end
  end
end
