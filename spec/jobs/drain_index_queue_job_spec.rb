# frozen_string_literal: true

require 'rails_helper'

RSpec.describe DrainIndexQueueJob do
  let(:redis) { instance_double(Redis, lrange: [], del: 1) }

  before do
    allow(Sidekiq).to receive(:redis).and_yield(redis)
    allow(Settings.indexing).to receive(:batch_size).and_return(10)
  end

  context 'when the pending files list is empty' do
    it 'does not enqueue any indexing jobs' do
      expect { described_class.perform_now }.not_to enqueue_job(IndexEadJob)
    end
  end

  context 'when the pending files list has fewer files than the batch size' do
    before { allow(redis).to receive(:lrange).and_return(['/data/ars/ars001.xml', '/data/ars/ars002.xml']) }

    it 'enqueues a single IndexEadJob with all files' do
      expect do
        described_class.perform_now
      end.to enqueue_job(IndexEadJob).once.with(file_paths: ['/data/ars/ars001.xml', '/data/ars/ars002.xml'])
    end

    it 'clears the Redis list' do
      described_class.perform_now
      expect(redis).to have_received(:del).with(DrainIndexQueueJob::PENDING_FILES_KEY)
    end
  end

  context 'when the pending files list exceeds the batch size' do
    let(:ars_files) { (1..12).map { |i| "/data/ars/ars#{format('%03d', i)}.xml" } }

    before { allow(redis).to receive(:lrange).and_return(ars_files) }

    it 'enqueues multiple IndexEadJobs respecting the batch size' do
      expect do
        described_class.perform_now
      end.to enqueue_job(IndexEadJob).exactly(2).times
    end

    it 'puts the first 10 files in the first batch' do
      expect do
        described_class.perform_now
      end.to enqueue_job(IndexEadJob).with(file_paths: ars_files.first(10))
    end

    it 'puts the remaining files in the last batch' do
      expect do
        described_class.perform_now
      end.to enqueue_job(IndexEadJob).with(file_paths: ars_files.last(2))
    end
  end

  context 'when files from multiple repositories are pending' do
    let(:ars_files) { ['/data/ars/ars001.xml', '/data/ars/ars002.xml'] }
    let(:eal_files) { ['/data/eal/eal001.xml'] }

    before { allow(redis).to receive(:lrange).and_return(ars_files + eal_files) }

    it 'enqueues a separate IndexEadJob per repository' do
      expect do
        described_class.perform_now
      end.to enqueue_job(IndexEadJob).exactly(2).times
    end

    it 'groups ars files into one job' do
      expect do
        described_class.perform_now
      end.to enqueue_job(IndexEadJob).with(file_paths: ars_files)
    end

    it 'groups eal files into one job' do
      expect do
        described_class.perform_now
      end.to enqueue_job(IndexEadJob).with(file_paths: eal_files)
    end
  end
end
