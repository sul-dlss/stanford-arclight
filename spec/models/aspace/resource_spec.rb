# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Aspace::Resource do
  subject(:resource) do
    described_class.new(ead_id: 'scm.123/ more stuff.xml', uri: '/respositories/11/resources/22',
                        repository_code: 'speccoll')
  end

  it { expect(resource.uri).to eq '/respositories/11/resources/22' }
  it { expect(resource.repository_code).to eq 'speccoll' }

  describe '#file_name' do
    it 'forms an acceptable filename from an eadid' do
      expect(resource.file_name).to eq 'scm-123-more-stuff'
    end

    context 'when only an identifier is provided in the resource' do
      subject(:resource) do
        described_class.new(identifier: 'scm-123morestuff', uri: '/respositories/11/resources/22',
                            repository_code: 'speccoll')
      end

      it 'forms an acceptable filename from an identifier' do
        expect(resource.file_name).to eq 'scm-123morestuff'
      end
    end

    context 'when no EAD ID or identifier is provided in the resource' do
      subject(:resource) do
        described_class.new(uri: '/respositories/11/resources/22', repository_code: 'speccoll')
      end

      it 'raises an error when file_name is called' do
        expect { resource.file_name }.to raise_error(Aspace::AspaceResourceError)
      end
    end
  end

  describe '#arclight_repository_code' do
    it 'converts the aspace repository code into an arclight repository code' do
      expect(resource.arclight_repository_code).to eq 'uarc'
    end

    context 'when only an identifier is provided in the resource' do
      subject(:resource) do
        described_class.new(identifier: 'scm-123morestuff', uri: '/respositories/11/resources/22',
                            repository_code: 'speccoll')
      end

      it 'converts the aspace repository code into an arclight repository code' do
        expect(resource.arclight_repository_code).to eq 'uarc'
      end
    end

    context 'when no EAD ID or identifier is provided in the resource' do
      subject(:resource) do
        described_class.new(uri: '/respositories/11/resources/22', repository_code: 'speccoll')
      end

      it 'raises an error when arclight_repository_code is called' do
        expect { resource.arclight_repository_code }.to raise_error(Aspace::AspaceResourceError)
      end
    end
  end
end
