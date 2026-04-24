# frozen_string_literal: true

##
# Drains the Redis list of EAD file paths accumulated by DownloadEadJob and
# enqueues batched IndexEadJobs grouped by repository. Files from the same
# repository directory are batched together so traject receives the correct
# REPOSITORY_ID for the whole batch.
class DrainIndexQueueJob < ApplicationJob
  PENDING_FILES_KEY = 'index_ead:pending_files'

  sidekiq_options unique_for: 10.minutes, retry: false

  def perform
    file_paths = pending_file_paths
    return if file_paths.blank?

    enqueue_batched_jobs(file_paths)
  end

  private

  def pending_file_paths
    Sidekiq.redis do |redis|
      paths = redis.lrange(PENDING_FILES_KEY, 0, -1)
      redis.del(PENDING_FILES_KEY) if paths.any?
      paths
    end
  end

  def enqueue_batched_jobs(file_paths)
    file_paths
      .group_by { |path| File.dirname(path) }
      .each_value { |paths| enqueue_slices(paths) }
  end

  def enqueue_slices(paths)
    paths.each_slice(Settings.indexing.batch_size) do |batch|
      IndexEadJob.perform_later(file_paths: batch)
    end
  end
end
