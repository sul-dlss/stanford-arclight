# frozen_string_literal: true

require 'rails_helper'

RSpec.describe SolrDocument do
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
end
