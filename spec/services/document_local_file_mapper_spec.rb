# frozen_string_literal: true

require 'rails_helper'

RSpec.describe DocumentLocalFileMapper do
  let(:document) do
    SolrDocument.new(
      id: 'ars0001',
      level_ssm: ['collection'],
      ead_filename_ssi: 'ars0001.xml'
    )
  end
  let(:data_dir) { '/data' }

  before do
    allow(Settings).to receive(:data_dir).and_return(data_dir)
    allow(document).to receive(:repository_config).and_return(
      Arclight::Repository.new(slug: 'ars')
    )
  end

  describe '#path' do
    context 'when ead_filename is populated' do
      context 'when the format is not specified' do
        let(:mapper) { described_class.new(document:) }

        it 'returns the path to the EAD XML file' do
          expect(mapper.path).to eq('/data/ars/ars0001.xml')
        end
      end

      context 'when the format is :ead' do
        let(:mapper) { described_class.new(document:, format: :ead) }

        it 'returns the path to the EAD XML file' do
          expect(mapper.path).to eq('/data/ars/ars0001.xml')
        end
      end

      context 'when the format is :xml' do
        let(:mapper) { described_class.new(document:, format: :xml) }

        it 'returns the path to the EAD XML file' do
          expect(mapper.path).to eq('/data/ars/ars0001.xml')
        end
      end

      context 'when the format is :pdf' do
        let(:mapper) { described_class.new(document:, format: :pdf) }

        it 'returns the path to the EAD PDF file' do
          expect(mapper.path).to eq('/data/ars/ars0001.pdf')
        end
      end
    end

    context 'when ead_filename is empty' do
      let(:document) do
        SolrDocument.new(
          id: 'ars0001',
          level_ssm: ['collection'],
          ead_filename_ssi: ''
        )
      end

      context 'when the format is :xml' do
        let(:mapper) { described_class.new(document:, format: :xml) }

        it 'returns nil' do
          expect(mapper.path).to eq(nil)
        end
      end

      context 'when the format is :pdf' do
        let(:mapper) { described_class.new(document:, format: :pdf) }

        it 'returns nil' do
          expect(mapper.path).to eq(nil)
        end
      end
    end

    context 'when the format is not supported' do
      let(:mapper) { described_class.new(document:, format: :zip) }

      it 'raises an error' do
        expect { mapper.path }.to raise_error(described_class::UnsupportedFormatError, 'Unsupported format: zip')
      end
    end
  end

  describe '#size' do
    let(:mapper) { described_class.new(document:, format: :xml) }

    context 'when the file path is present and the file exists' do
      it 'returns the size of the file' do
        allow(File).to receive(:exist?).and_return(true)
        allow(File).to receive(:size).and_return(1000)
        expect(mapper.size).to eq(1000)
      end
    end

    context 'when the file path is present but the file does not exist' do
      it 'returns nil' do
        allow(File).to receive(:exist?).and_return(false)
        expect(mapper.size).to eq(nil)
      end
    end

    context 'when the file path is missing' do
      it 'returns nil' do
        allow(mapper).to receive(:path).and_return(nil)
        expect(mapper.size).to eq(nil)
      end
    end
  end
end
