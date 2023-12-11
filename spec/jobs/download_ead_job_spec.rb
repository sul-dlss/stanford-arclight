# frozen_string_literal: true

require 'rails_helper'

RSpec.describe DownloadEadJob do
  let(:client) { instance_double(AspaceClient, resource_description: '<a/>') }
  let(:file) { instance_double(File, puts: true) }

  before do
    allow(AspaceClient).to receive(:new).and_return(client)
    allow(File).to receive(:open).and_yield(file)
  end

  it 'fetches an EAD from the client service' do
    described_class.perform_now(resource_uri: 'resource/abc123', file_name: 'abc123', data_dir: '/data/archive/')

    expect(client).to have_received(:resource_description).with('resource/abc123')
  end

  it 'writes the formatted EAD XML to a file' do
    described_class.perform_now(resource_uri: 'resource/abc123', file_name: 'abc123', data_dir: '/data/archive/')

    expect(file).to have_received(:puts).with("<?xml version=\"1.0\"?>\n<a/>\n")
  end

  context 'when index param value is true' do
    it 'enqueues an indexing job with the EAD file' do
      expect do
        described_class.perform_now(resource_uri: 'resource/abc123', file_name: 'abc123', data_dir: '/data/archive/',
                                    index: true)
      end.to enqueue_job(IndexEadJob).once.with(file_path: '/data/archive/abc123.xml')
    end
  end
end
