# frozen_string_literal: true

# Tracks the last time each ArchivesSpace repository was successfully synced.
# Used to provide a precise updated_after timestamp for frequent incremental syncs.
class AspaceRepositorySync < ApplicationRecord
  # @param repository [Aspace::Repository]
  # @return [Time, nil] the last synced time, or nil if never synced
  def self.last_synced_at_for(repository)
    find_by(aspace_config_set: repository.aspace_config_set.to_s,
            repository_code: repository.code)&.last_synced_at
  end

  # @param repository [Aspace::Repository]
  # @param synced_at [Time]
  def self.record_sync(repository:, synced_at:)
    find_or_initialize_by(aspace_config_set: repository.aspace_config_set.to_s,
                          repository_code: repository.code)
      .update!(last_synced_at: synced_at)
  end
end
