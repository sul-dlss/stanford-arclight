# frozen_string_literal: true

require 'rails_helper'

RSpec.describe EnqueueRepositoryDownload do
  let(:repository) { instance_double(Aspace::Repository, aspace_config_set: :default) }
  let(:check_record_dates) { false }
  let(:config) do
    instance_double(
      DownloadEadJob::Config,
      updated_after: nil,
      check_record_dates: check_record_dates,
      data_directory: '/tmp/data',
      index: false,
      generate_pdf: false
    )
  end
  let(:first_resource) do
    instance_double(
      Aspace::Resource,
      uri: '/repositories/1/resources/1',
      file_name: 'resource1.xml',
      arclight_repository_code: 'repo1'
    )
  end
  let(:secound_resource) do
    instance_double(
      Aspace::Resource,
      uri: '/repositories/1/resources/2',
      file_name: 'resource2.xml',
      arclight_repository_code: 'repo1'
    )
  end

  describe '.call' do
    before do
      allow(repository).to receive(:each_published_resource).and_yield(first_resource).and_yield(secound_resource)
      allow(DownloadEadJob).to receive(:perform_later)
    end

    it 'enqueues resources for download' do
      described_class.call(repository:, config:)
      expect(repository).to have_received(:each_published_resource).exactly(1).time
      expect(DownloadEadJob).to have_received(:perform_later).exactly(2).times
    end

    context 'when checking for updated components and agents' do
      let(:check_record_dates) { true }

      before do
        allow(repository).to receive(:each_published_resource_with_updated_components).and_raise(ArgumentError)
      end

      it 'used the fallback strategy when an ArgumentError is raised' do
        described_class.call(repository:, config:)
        expect(repository).to have_received(:each_published_resource).exactly(2).times
        expect(DownloadEadJob).to have_received(:perform_later).exactly(2).times
      end
    end
  end
end
