# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Aspace::Resource do
  subject(:resource) do
    described_class.new(ead_id: 'scm.123/ more stuff.xml', uri: '/respositories/11/resources/22',
                        repository_code: 'speccoll')
  end

  it { expect(resource.ead_id).to eq 'scm.123/ more stuff.xml' }
  it { expect(resource.uri).to eq '/respositories/11/resources/22' }
  it { expect(resource.repository_code).to eq 'speccoll' }

  describe '#file_name' do
    it 'forms an acceptable filename from an eadid' do
      expect(resource.file_name).to eq 'scm-123-more-stuff'
    end
  end

  describe '#arclight_repository_code' do
    it 'converts the aspace repository code into an arclight repository code' do
      expect(resource.arclight_repository_code).to eq 'uarc'
    end
  end
end
